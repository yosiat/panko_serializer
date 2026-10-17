# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen/writers_pool"

RSpec.describe Panko::CodeGen::WritersPool do
  let(:small_result) { "{}" }
  let(:max_bytes) { 64 }
  let(:large_result) { "x" * (max_bytes + 1) }

  around do |example|
    original_max_bytes = Panko::Config.writer_pool_max_bytes
    Panko::Config.writer_pool_max_bytes = max_bytes
    example.run
  ensure
    Panko::Config.writer_pool_max_bytes = original_max_bytes
  end

  def count_new_writers
    count = 0
    original = Oj::StringWriter.method(:new)
    allow(Oj::StringWriter).to receive(:new) do |*args, **kwargs|
      count += 1
      original.call(*args, **kwargs)
    end
    yield
    count
  end

  describe "abstract base" do
    it "raises NotImplementedError on checkout, since #storage is unimplemented" do
      expect { described_class.new.checkout }
        .to raise_error(NotImplementedError, /must override #storage/)
    end
  end

  describe Panko::CodeGen::WritersPool::ThreadLocal do
    subject(:pool) { described_class.new }

    around do |example|
      Thread.current[Panko::CodeGen::WritersPool::STORAGE_KEY] = nil
      example.run
    ensure
      Thread.current[Panko::CodeGen::WritersPool::STORAGE_KEY] = nil
    end

    describe "#checkout" do
      it "allocates a fresh Oj::StringWriter when the stack is empty" do
        expect(pool.checkout).to be_a(Oj::StringWriter)
      end

      it "returns the same Oj::StringWriter instance after a small checkin (proves reuse)" do
        first = pool.checkout
        pool.checkin(first, small_result)

        expect(pool.checkout).to equal(first)
      end

      it "returns two distinct Writer instances on two checkouts before any checkin (reentrancy)" do
        first = pool.checkout
        second = pool.checkout

        expect(second).not_to equal(first)
      end
    end

    describe "#checkin" do
      it "clears the Writer's buffer so the next checkout sees an empty to_s" do
        writer = pool.checkout
        writer.push_object
        writer.push_value(1, "id")
        writer.pop
        pool.checkin(writer, writer.to_s)

        reused = pool.checkout
        expect(reused).to equal(writer)
        expect(reused.to_s).to eq("")
      end

      it "keeps a Writer whose result is exactly writer_pool_max_bytes" do
        writer = pool.checkout
        pool.checkin(writer, "x" * max_bytes)

        expect(pool.checkout).to equal(writer)
      end

      it "drops a Writer whose result is larger than writer_pool_max_bytes" do
        writer = pool.checkout
        pool.checkin(writer, large_result)

        expect(pool.checkout).not_to equal(writer)
      end

      it "drops a Writer checked in with a nil result (the body raised)" do
        writer = pool.checkout
        pool.checkin(writer, nil)

        expect(pool.checkout).not_to equal(writer)
      end

      it "reads writer_pool_max_bytes at checkin, so a changed setting applies to the next call" do
        writer = pool.checkout
        Panko::Config.writer_pool_max_bytes = large_result.bytesize
        pool.checkin(writer, large_result)

        expect(pool.checkout).to equal(writer)
      end
    end

    describe "one stack per thread" do
      it "hands a Writer checked in by one pool to a checkout on another pool" do
        other_pool = described_class.new
        writer = pool.checkout
        pool.checkin(writer, small_result)

        expect(other_pool.checkout).to equal(writer)
      end
    end

    describe "steady state" do
      it "calls Oj::StringWriter.new once across 10_000 serial cycles" do
        created = count_new_writers do
          10_000.times do
            writer = pool.checkout
            pool.checkin(writer, small_result)
          end
        end

        expect(created).to eq(1)
      end

      it "calls Oj::StringWriter.new twice across 10_000 reentrant cycles" do
        created = count_new_writers do
          10_000.times do
            outer = pool.checkout
            inner = pool.checkout
            pool.checkin(inner, small_result)
            pool.checkin(outer, small_result)
          end
        end

        expect(created).to eq(2)
      end

      it "calls Oj::StringWriter.new on every cycle whose result is over the limit" do
        cycles = 10
        created = count_new_writers do
          cycles.times do
            writer = pool.checkout
            pool.checkin(writer, large_result)
          end
        end

        expect(created).to eq(cycles)
      end
    end

    describe "fiber-local isolation (Thread#[] is fiber-local)" do
      it "does not surface a Fiber's checked-in Writer to a sibling Fiber's checkout" do
        a_writer = nil
        b_writer = nil

        f_a = Fiber.new do
          a_writer = pool.checkout
          pool.checkin(a_writer, small_result)
          Fiber.yield
        end
        f_b = Fiber.new do
          b_writer = pool.checkout
        end

        f_a.resume
        f_b.resume
        f_a.resume

        expect(b_writer).not_to equal(a_writer)
      end
    end
  end

  describe Panko::CodeGen::WritersPool::IsolatedExecutionState do
    subject(:pool) { described_class.new }

    around do |example|
      skip "ActiveSupport::IsolatedExecutionState not loaded" unless defined?(ActiveSupport::IsolatedExecutionState)
      ActiveSupport::IsolatedExecutionState.delete(Panko::CodeGen::WritersPool::STORAGE_KEY)
      example.run
    ensure
      ActiveSupport::IsolatedExecutionState.delete(Panko::CodeGen::WritersPool::STORAGE_KEY) if defined?(ActiveSupport::IsolatedExecutionState)
    end

    it "allocates a fresh Oj::StringWriter when the stack is empty" do
      expect(pool.checkout).to be_a(Oj::StringWriter)
    end

    it "reuses the same Oj::StringWriter instance after a small checkin" do
      first = pool.checkout
      pool.checkin(first, small_result)

      expect(pool.checkout).to equal(first)
    end

    it "drops a Writer whose result is larger than writer_pool_max_bytes" do
      writer = pool.checkout
      pool.checkin(writer, large_result)

      expect(pool.checkout).not_to equal(writer)
    end

    it "does not surface a Fiber's checked-in Writer to a sibling Fiber when isolation_level is :fiber" do
      prior = ActiveSupport::IsolatedExecutionState.isolation_level
      ActiveSupport::IsolatedExecutionState.isolation_level = :fiber
      a_writer = nil
      b_writer = nil
      begin
        f_a = Fiber.new do
          a_writer = pool.checkout
          pool.checkin(a_writer, small_result)
          Fiber.yield
        end
        f_b = Fiber.new do
          b_writer = pool.checkout
        end

        f_a.resume
        f_b.resume
        f_a.resume

        expect(b_writer).not_to equal(a_writer)
      ensure
        ActiveSupport::IsolatedExecutionState.isolation_level = prior
      end
    end
  end
end
