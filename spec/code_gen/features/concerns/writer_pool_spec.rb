# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "shallow_generic"
require "nested_composition"

# Cross-cutting +WritersPool+ contract — the feature-level integration
# tier from +PRD #82+. The pool's unit semantics are
# pinned in +spec/writers_pool_spec.rb+; the JSON-mode emit shape in
# +spec/generators/writer_pool_emit_spec.rb+ + the regenerated
# +spec/fixtures/generated/*_json.rb+ snapshots; this file pins what the
# unit specs cannot reach — multi-thread stress, mid-emit fiber yielding,
# Method Attribute bodies that re-enter +serialize_one+ cross-class and
# same-class, exception recovery via the caller's +ensure+, and pooled
# vs unpooled output parity.
#
# The +ThreadLocal+ backend is forced (via +hide_const+ around +Compile+)
# wherever the test exercises fiber-locality semantics — +Thread.current[]+ is
# fiber-local in MRI; +ActiveSupport::IsolatedExecutionState+'s default
# +isolation_level+ is +:thread+ in CI cells without an explicit Falcon
# binding, so an IES-backed pool would spuriously share storage between
# fibers in the same thread and mask the fiber-locality claim. The
# threading + reentrancy + exception + parity tests run on the default
# config (whichever subclass +defined?(AS::IES)+ picks) — the pool's
# documented contract is invariant across both backends at the spec
# tier.
RSpec.describe "WritersPool — feature-level pool contract" do
  # Every Generated Class shares one stack per thread, so writers left by
  # earlier examples would change the allocation counts asserted here.
  def clear_writer_stacks
    Thread.current[Panko::CodeGen::WritersPool::STORAGE_KEY] = nil
    ActiveSupport::IsolatedExecutionState.delete(Panko::CodeGen::WritersPool::STORAGE_KEY) if defined?(ActiveSupport::IsolatedExecutionState)
  end

  around do |example|
    clear_writer_stacks
    example.run
  ensure
    clear_writer_stacks
  end

  describe "thread isolation" do
    # Spawn N threads each calling +serialize_one+ in a tight loop and
    # assert every output is the canonical fixture string. A
    # globally-shared (non-per-thread) Writer would interleave bytes
    # across threads and at least one output would diverge; per-thread
    # storage produces +N × M+ correct outputs.
    it "produces correct output across 8 threads × 1000 calls each" do
      descriptor = Fixtures::ShallowGeneric::DESCRIPTOR
      generated = Panko::CodeGen.compile(descriptor, output: :json, config: Fixtures::ShallowGeneric::CONFIG)
        .new(descriptor: descriptor)
      record = Fixtures::ShallowGeneric.sanity_record
      expected = Fixtures::ShallowGeneric.expected_output(:json)

      threads = Array.new(8) do
        Thread.new do
          1000.times.map { generated.serialize_one(record) }
        end
      end
      results = threads.flat_map(&:value)

      expect(results.size).to eq(8000)
      expect(results.uniq).to eq([expected])
    end
  end

  describe "fiber isolation under manual scheduler" do
    # Two
    # +Fiber+s yielding mid-emit (a Method Attribute body that calls
    # +Fiber.yield+) each produce correct output. +Thread.current[]+ is
    # fiber-local per MRI +thread.c:3812+; the +ThreadLocal+ backend
    # propagates that locality straight through.
    before do
      hide_const("ActiveSupport::IsolatedExecutionState") if defined?(ActiveSupport::IsolatedExecutionState)
    end

    it "two Fibers yielding mid-emit each produce correct output" do
      yielding_descriptor = Panko::CodeGen::Descriptor.new(
        name: "WriterPoolFiberYieldSerializer",
        model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
        method_attributes: [
          Panko::CodeGen::MethodAttribute.new(
            name: :name,
            body: ->(record, _context) {
              Fiber.yield
              record["name"]
            }
          )
        ],
        associations: []
      )
      generated = Panko::CodeGen.compile(yielding_descriptor, output: :json)
        .new(descriptor: yielding_descriptor)

      result_a = nil
      result_b = nil
      f_a = Fiber.new { result_a = generated.serialize_one({"id" => 1, "name" => "alice"}) }
      f_b = Fiber.new { result_b = generated.serialize_one({"id" => 2, "name" => "bob"}) }

      f_a.resume
      f_b.resume
      f_a.resume
      f_b.resume

      expect(result_a).to eq('{"id":1,"name":"alice"}')
      expect(result_b).to eq('{"id":2,"name":"bob"}')
    end
  end

  describe "cross-class reentrancy" do
    # A Method Attribute body that calls a different Generated Class's
    # +serialize_one(other_record)+ mid-emit. The inner call finds the
    # shared stack empty (the outer holds its Writer) and takes a second
    # one; the outer's Writer state survives the nested call; both outputs
    # are correct.
    it "outer + inner outputs are correct when an outer Method Attribute calls a different Generated Class's serialize_one" do
      inner_descriptor = Panko::CodeGen::Descriptor.new(
        name: "WriterPoolCrossClassInnerSerializer",
        model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [
          Panko::CodeGen::Attribute.new(name: :id, source: :id),
          Panko::CodeGen::Attribute.new(name: :tag, source: :tag)
        ],
        method_attributes: [],
        associations: []
      )
      inner = Panko::CodeGen.compile(inner_descriptor, output: :json)
        .new(descriptor: inner_descriptor)

      outer_descriptor = Panko::CodeGen::Descriptor.new(
        name: "WriterPoolCrossClassOuterSerializer",
        model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
        method_attributes: [
          Panko::CodeGen::MethodAttribute.new(
            name: :embedded,
            body: ->(record, _context) { inner.serialize_one(record["embedded"]) }
          )
        ],
        associations: []
      )
      outer = Panko::CodeGen.compile(outer_descriptor, output: :json)
        .new(descriptor: outer_descriptor)

      record = {"id" => 1, "embedded" => {"id" => 99, "tag" => "x"}}
      result = outer.serialize_one(record)

      expect(result).to eq('{"id":1,"embedded":"{\"id\":99,\"tag\":\"x\"}"}')
    end
  end

  describe "same-class reentrancy" do
    # A Method Attribute body that calls its own +Klass#serialize_one+
    # recursively. The pool grows to depth 2 on the first cycle (outer
    # checks out writer_1, body re-enters and checks out writer_2 from
    # the now-empty stack) and then reuses both on every subsequent
    # cycle — total +Oj::StringWriter.new+ across 1000 cycles is exactly
    # 2.
    it "allocates exactly 2 Oj::StringWriter instances across 1000 reentrant cycles" do
      depth = 0
      generated = nil
      reentrant_descriptor = Panko::CodeGen::Descriptor.new(
        name: "WriterPoolSameClassReentrantSerializer",
        model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
        method_attributes: [
          Panko::CodeGen::MethodAttribute.new(
            name: :child,
            body: ->(record, _context) {
              if depth >= 1
                nil
              else
                depth += 1
                begin
                  generated.serialize_one({"id" => -record["id"]})
                ensure
                  depth -= 1
                end
              end
            }
          )
        ],
        associations: []
      )
      generated = Panko::CodeGen.compile(reentrant_descriptor, output: :json)
        .new(descriptor: reentrant_descriptor)

      call_count = 0
      original_new = Oj::StringWriter.method(:new)
      allow(Oj::StringWriter).to receive(:new) do |*args, **kwargs|
        call_count += 1
        original_new.call(*args, **kwargs)
      end

      results = 1000.times.map { |i| generated.serialize_one({"id" => i + 1}) }

      expect(call_count).to eq(2)
      expect(results.first).to eq('{"id":1,"child":"{\"id\":-1,\"child\":null}"}')
      expect(results.last).to eq('{"id":1000,"child":"{\"id\":-1000,\"child\":null}"}')
    end
  end

  describe "exception recovery" do
    # A Method Attribute body that raises mid-emit. The outer's +ensure+
    # hands +checkin+ a nil result, which drops the half-written Writer,
    # so the next +serialize_one+ call starts from a clean one.
    it "next serialize_one after a mid-emit raise produces correct output" do
      should_raise = true
      raising_descriptor = Panko::CodeGen::Descriptor.new(
        name: "WriterPoolExceptionRecoverySerializer",
        model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
        method_attributes: [
          Panko::CodeGen::MethodAttribute.new(
            name: :name,
            body: ->(record, _context) {
              raise "boom" if should_raise
              record["name"]
            }
          )
        ],
        associations: []
      )
      generated = Panko::CodeGen.compile(raising_descriptor, output: :json)
        .new(descriptor: raising_descriptor)

      expect {
        generated.serialize_one({"id" => 1, "name" => "alice"})
      }.to raise_error("boom")

      should_raise = false
      expect(generated.serialize_one({"id" => 2, "name" => "bob"}))
        .to eq('{"id":2,"name":"bob"}')
    end
  end

  describe "one writer shared by every Generated Class on a thread" do
    it "creates one Oj::StringWriter for two different classes serialized one after another" do
      shallow = Panko::CodeGen.compile(Fixtures::ShallowGeneric::DESCRIPTOR, output: :json, config: Fixtures::ShallowGeneric::CONFIG)
        .new(descriptor: Fixtures::ShallowGeneric::DESCRIPTOR)
      nested = Panko::CodeGen.compile(Fixtures::NestedComposition::DESCRIPTOR, output: :json, config: Fixtures::NestedComposition::CONFIG)
        .new(descriptor: Fixtures::NestedComposition::DESCRIPTOR)
      shallow.serialize_one(Fixtures::ShallowGeneric.sanity_record)

      created = 0
      original_new = Oj::StringWriter.method(:new)
      allow(Oj::StringWriter).to receive(:new) do |*args, **kwargs|
        created += 1
        original_new.call(*args, **kwargs)
      end

      10.times do
        shallow.serialize_one(Fixtures::ShallowGeneric.sanity_record)
        nested.serialize_one(Fixtures::NestedComposition.sanity_record)
      end

      expect(created).to eq(0)
    end
  end

  describe "output size limit" do
    let(:max_bytes) { 256 }
    let(:records) { Array.new(20) { Fixtures::ShallowGeneric.sanity_record } }
    let(:calls) { 5 }
    let(:generated) do
      Panko::CodeGen.compile(Fixtures::ShallowGeneric::DESCRIPTOR, output: :json, config: Fixtures::ShallowGeneric::CONFIG)
        .new(descriptor: Fixtures::ShallowGeneric::DESCRIPTOR)
    end

    around do |example|
      original_max_bytes = Panko::Config.writer_pool_max_bytes
      Panko::Config.writer_pool_max_bytes = max_bytes
      example.run
    ensure
      Panko::Config.writer_pool_max_bytes = original_max_bytes
    end

    it "does not reuse the writer of an output larger than writer_pool_max_bytes" do
      expect(generated.serialize_many(records).bytesize).to be > max_bytes

      created = 0
      original_new = Oj::StringWriter.method(:new)
      allow(Oj::StringWriter).to receive(:new) do |*args, **kwargs|
        created += 1
        original_new.call(*args, **kwargs)
      end
      calls.times { generated.serialize_many(records) }

      expect(created).to eq(calls)
    end

    it "keeps output byte-identical when the writer is dropped" do
      unpooled_config = Panko::CodeGen::Config.new(**Fixtures::ShallowGeneric::CONFIG.to_h.merge(pool_writer: false))
      unpooled = Panko::CodeGen.compile(Fixtures::ShallowGeneric::DESCRIPTOR, output: :json, config: unpooled_config)
        .new(descriptor: Fixtures::ShallowGeneric::DESCRIPTOR)

      expect(generated.serialize_many(records)).to eq(unpooled.serialize_many(records))
    end
  end

  describe "pooled-vs-unpooled output parity" do
    # The byte-identical-output bar from the PRD: setting
    # +Config#pool_writer: false+ is a one-line emergency rollback that
    # must produce the exact same output as the pooled path. Every
    # representative fixture sample exercises the parity contract.
    fixture_samples = [
      [Fixtures::ShallowGeneric, Fixtures::ShallowGeneric.sanity_record],
      [Fixtures::NestedComposition, Fixtures::NestedComposition.sanity_record]
    ]

    fixture_samples.each do |fixture, record|
      it "produces byte-identical JSON for #{fixture.name} under pool_writer: true vs false" do
        pooled_config = Panko::CodeGen::Config.new(**fixture::CONFIG.to_h.merge(pool_writer: true))
        unpooled_config = Panko::CodeGen::Config.new(**fixture::CONFIG.to_h.merge(pool_writer: false))

        pooled = Panko::CodeGen.compile(fixture::DESCRIPTOR, output: :json, config: pooled_config)
          .new(descriptor: fixture::DESCRIPTOR)
        unpooled = Panko::CodeGen.compile(fixture::DESCRIPTOR, output: :json, config: unpooled_config)
          .new(descriptor: fixture::DESCRIPTOR)

        pooled_one = pooled.serialize_one(record)
        unpooled_one = unpooled.serialize_one(record)
        pooled_many = pooled.serialize_many([record, record])
        unpooled_many = unpooled.serialize_many([record, record])

        expect(pooled_one).to eq(unpooled_one)
        expect(pooled_many).to eq(unpooled_many)
        expect(pooled_one).to eq(fixture.expected_output(:json))
      end
    end
  end
end
