# frozen_string_literal: true

require "spec_helper"
require "serializers_code_gen"

# Cross-cutting +Association#if+ contract — the 10-item enumeration from
# +docs/testing.md § association_if_spec.rb+. JSON/Hash parity is iterated
# at the describe block per +docs/testing.md § JSON/Hash parity+ (this is
# item (10) and pins the parallel emit shapes per +docs/output-modes.md+).
# Fixtures are inline minimal Descriptors (1 +has_one+ or +has_many+
# Association each, plus 1 +id+ Attribute on parent + child); the
# +nested_composition+ fixture's snapshot pins the emit bytes for the
# +has_one+ + +if:+ shape, this file pins the runtime semantics across
# Kinds, arities, return values, and the cardinality contract.
#
# Precedence ladder (per +docs/testing.md § association_if_spec.rb §
# Precedence ladder+, also +docs/filters.md+):
#
#   1. Filter.drops?(:assoc) → omit; if: not invoked, Source not called.
#   2. if: present and returns falsy → omit; Source not called.
#   3. if: truthy (or absent) → call Source.
#      3a. Source returns an object → serialize (the normal case).
#      3b. Source returns nil:
#           - null_for_missing_has_one: true  → emit "assoc": null
#           - null_for_missing_has_one: false → omit the key
#
# Filter (1) is phase-2-locked; only (2)/(3) are exercised here. The
# orthogonality of +if:+ vs +null_for_missing_has_one+ — (2) wins over
# (3b) at both config values — is item (3) of the contract.
RSpec.describe "Association if: — Callable guard contract" do
  def inner_descriptor
    SerializersCodeGen::Descriptor.new(
      name: "InnerSerializer",
      models: nil,
      attributes: [SerializersCodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [],
      associations: []
    )
  end

  def descriptor_with(name: "ParentSerializer", associations: [])
    SerializersCodeGen::Descriptor.new(
      name: name,
      models: nil,
      attributes: [SerializersCodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [],
      associations: associations
    )
  end

  def has_one(name = :child, descriptor: inner_descriptor, if: nil)
    SerializersCodeGen::Association.new(
      name: name, kind: :has_one, descriptor: descriptor, if: binding.local_variable_get(:if)
    )
  end

  def has_many(name = :children, descriptor: inner_descriptor, if: nil)
    SerializersCodeGen::Association.new(
      name: name, kind: :has_many, descriptor: descriptor, if: binding.local_variable_get(:if)
    )
  end

  def compile(descriptor, mode, config: SerializersCodeGen::Config.new)
    SerializersCodeGen.compile(descriptor, output: mode, config: config).new(descriptor: descriptor)
  end

  describe "(1) Truthy return → Association included (non-boolean truthy values count)" do
    [true, 0, "", [], {}].each do |truthy|
      %i[json hash].each do |mode|
        context "with if: returning #{truthy.inspect} in #{mode} mode" do
          it "emits the Association key" do
            descriptor = descriptor_with(associations: [has_one(:child, if: ->(_r, _c) { truthy })])
            generated = compile(descriptor, mode)
            record = {"id" => 1, "child" => {"id" => 7}}
            expected = (mode == :json) ? '{"id":1,"child":{"id":7}}' : {"id" => 1, "child" => {"id" => 7}}
            expect(generated.serialize_one(record)).to eq(expected)
          end
        end
      end
    end
  end

  describe "(2) Falsy return (nil, false) → key omitted entirely (not null, not [], not {})" do
    [nil, false].each do |falsy|
      %i[json hash].each do |mode|
        context "with if: returning #{falsy.inspect} in #{mode} mode" do
          it "omits the has_one key entirely" do
            descriptor = descriptor_with(associations: [has_one(:child, if: ->(_r, _c) { falsy })])
            generated = compile(descriptor, mode)
            record = {"id" => 1, "child" => {"id" => 7}}
            expected = (mode == :json) ? '{"id":1}' : {"id" => 1}
            expect(generated.serialize_one(record)).to eq(expected)
          end

          it "omits the has_many key entirely" do
            descriptor = descriptor_with(associations: [has_many(:children, if: ->(_r, _c) { falsy })])
            generated = compile(descriptor, mode)
            record = {"id" => 1, "children" => [{"id" => 7}, {"id" => 8}]}
            expected = (mode == :json) ? '{"id":1}' : {"id" => 1}
            expect(generated.serialize_one(record)).to eq(expected)
          end
        end
      end
    end
  end

  describe "(3) has_one + if: falsy → omitted regardless of null_for_missing_has_one" do
    [true, false].each do |null_for_missing|
      %i[json hash].each do |mode|
        context "with null_for_missing_has_one: #{null_for_missing} in #{mode} mode" do
          it "omits the key (not null) when if: is falsy — orthogonal omission paths" do
            config = SerializersCodeGen::Config.new(null_for_missing_has_one: null_for_missing)
            descriptor = descriptor_with(associations: [has_one(:child, if: ->(_r, _c) { false })])
            generated = compile(descriptor, mode, config: config)
            # Record carries a real child — Source would emit it if not for the if: gate.
            record = {"id" => 1, "child" => {"id" => 7}}
            expected = (mode == :json) ? '{"id":1}' : {"id" => 1}
            expect(generated.serialize_one(record)).to eq(expected)
          end
        end
      end
    end
  end

  describe "(4) has_many + if: falsy → omitted (not [])" do
    %i[json hash].each do |mode|
      context "with #{mode} mode" do
        it "omits the key — does not emit an empty array" do
          descriptor = descriptor_with(associations: [has_many(:children, if: ->(_r, _c) { false })])
          generated = compile(descriptor, mode)
          record = {"id" => 1, "children" => [{"id" => 7}]}
          output = generated.serialize_one(record)
          if mode == :json
            expect(output).to eq('{"id":1}')
            expect(output).not_to include("[]")
            expect(output).not_to include("children")
          else
            expect(output).to eq({"id" => 1})
            expect(output).not_to have_key("children")
          end
        end
      end
    end
  end

  describe "(5) if: nil (no guard) → Association always emits — zero runtime cost" do
    %i[json hash].each do |mode|
      context "with #{mode} mode" do
        it "emits the has_one key without any if-branch (no @cb_if_<name> ivar hoisted)" do
          descriptor = descriptor_with(associations: [has_one(:child)]) # if: defaults to nil
          generated = compile(descriptor, mode)
          record = {"id" => 1, "child" => {"id" => 7}}
          expected = (mode == :json) ? '{"id":1,"child":{"id":7}}' : {"id" => 1, "child" => {"id" => 7}}
          expect(generated.serialize_one(record)).to eq(expected)
          # Pins "no @cb_if_<name> ivar hoisted" — the constructor body
          # only assigns the serializer ivar for an unguarded Association.
          expect(generated.instance_variables).not_to include(:@cb_if_child)
          expect(generated.instance_variables).to include(:@child_serializer)
        end

        it "emits the has_many key without any if-branch" do
          descriptor = descriptor_with(associations: [has_many(:children)])
          generated = compile(descriptor, mode)
          record = {"id" => 1, "children" => [{"id" => 7}]}
          expected = (mode == :json) ? '{"id":1,"children":[{"id":7}]}' : {"id" => 1, "children" => [{"id" => 7}]}
          expect(generated.serialize_one(record)).to eq(expected)
          expect(generated.instance_variables).not_to include(:@cb_if_children)
        end
      end
    end
  end

  describe "(6) Arity 0 — invoked with no arguments" do
    %i[json hash].each do |mode|
      context "with #{mode} mode" do
        it "calls a 0-arity Lambda with no args (Lambda would raise ArgumentError on extras)" do
          calls = []
          guard = -> {
            calls << :invoked
            true
          }
          expect(guard.arity).to eq(0)
          descriptor = descriptor_with(associations: [has_one(:child, if: guard)])
          generated = compile(descriptor, mode)
          expect {
            generated.serialize_one({"id" => 1, "child" => {"id" => 7}})
          }.not_to raise_error
          expect(calls).to eq([:invoked])
        end
      end
    end
  end

  describe "(7) Arity 1 — invoked with the Record" do
    %i[json hash].each do |mode|
      context "with #{mode} mode" do
        it "passes the Record positionally to a 1-arity Lambda" do
          captured = []
          guard = ->(record) {
            captured << record
            true
          }
          expect(guard.arity).to eq(1)
          descriptor = descriptor_with(associations: [has_one(:child, if: guard)])
          generated = compile(descriptor, mode)
          record = {"id" => 1, "child" => {"id" => 7}}
          generated.serialize_one(record)
          expect(captured.size).to eq(1)
          expect(captured.first).to equal(record)
        end
      end
    end
  end

  describe "(8) Arity 2 — invoked with (record, context); threads Context unchanged" do
    %i[json hash].each do |mode|
      context "with #{mode} mode" do
        it "passes the Record and Context positionally to a 2-arity Lambda" do
          captured_record = nil
          captured_context = nil
          guard = ->(record, context) {
            captured_record = record
            captured_context = context
            true
          }
          expect(guard.arity).to eq(2)
          descriptor = descriptor_with(associations: [has_one(:child, if: guard)])
          generated = compile(descriptor, mode)
          record = {"id" => 1, "child" => {"id" => 7}}
          context = {tenant: "acme"}
          generated.serialize_one(record, context: context)
          expect(captured_record).to equal(record)
          expect(captured_context).to equal(context)
        end

        it "threads context: nil unchanged when the caller omits the kwarg" do
          captured_context = :unset
          guard = ->(_record, context) {
            captured_context = context
            true
          }
          descriptor = descriptor_with(associations: [has_one(:child, if: guard)])
          generated = compile(descriptor, mode)
          generated.serialize_one({"id" => 1, "child" => {"id" => 7}})
          expect(captured_context).to be_nil
        end
      end
    end
  end

  describe "(9) Invocation cardinality — once per (Association, Record) per serialize call" do
    %i[json hash].each do |mode|
      context "with #{mode} mode" do
        it "invokes the if: spy exactly once for serialize_one with one Record" do
          count = 0
          guard = ->(_r, _c) {
            count += 1
            true
          }
          descriptor = descriptor_with(associations: [has_one(:child, if: guard)])
          generated = compile(descriptor, mode)
          generated.serialize_one({"id" => 1, "child" => {"id" => 7}})
          expect(count).to eq(1)
        end

        it "invokes the if: spy exactly N times for serialize_many of N Records (1 Association × N Records)" do
          count = 0
          guard = ->(_r, _c) {
            count += 1
            true
          }
          descriptor = descriptor_with(associations: [has_one(:child, if: guard)])
          generated = compile(descriptor, mode)
          records = [
            {"id" => 1, "child" => {"id" => 7}},
            {"id" => 2, "child" => {"id" => 8}},
            {"id" => 3, "child" => {"id" => 9}}
          ]
          generated.serialize_many(records)
          expect(count).to eq(3)
        end

        it "invokes a falsy-returning if: spy exactly once per Record (Source not called)" do
          # Pins precedence ladder step 2: if: present and returns falsy →
          # omit; Source not called. With +null_for_missing_has_one: true+
          # (default), if the Source had been invoked despite the falsy
          # guard, +record["child"]+ would return +nil+ (Hash default) and
          # the +has_one+ branch would emit +"child":null+. The exact-match
          # assertion on +'{"id":1}'+ would then fail — so observing the
          # bare +'{"id":1}'+ output proves the Source was skipped.
          count = 0
          guard = ->(_r, _c) {
            count += 1
            false
          }
          descriptor = descriptor_with(associations: [has_one(:child, if: guard)])
          generated = compile(descriptor, mode)
          output = generated.serialize_one({"id" => 1})
          expect(count).to eq(1)
          if mode == :json
            expect(output).to eq('{"id":1}')
          else
            expect(output).to eq({"id" => 1})
          end
        end
      end
    end
  end
end
