# frozen_string_literal: true

require "spec_helper"
require "serializers_code_gen/writers_pool"

RSpec.describe SerializersCodeGen::WritersPool do
  describe SerializersCodeGen::WritersPool::ThreadLocal do
    subject(:pool) { described_class.new(storage_key) }

    let(:storage_key) { :"_scg_writer_test_#{object_id}" }

    after { Thread.current[storage_key] = nil }

    describe "#checkout" do
      it "allocates a fresh Oj::StringWriter when the stack is empty" do
        writer = pool.checkout

        expect(writer).to be_a(Oj::StringWriter)
      end

      it "returns the same Oj::StringWriter instance after checkin (proves reuse)" do
        first = pool.checkout
        pool.checkin(first)
        second = pool.checkout

        expect(second).to equal(first)
      end

      it "returns two distinct Writer instances on two checkouts before any checkin (reentrancy)" do
        first = pool.checkout
        second = pool.checkout

        expect(second).not_to equal(first)
        expect(first).to be_a(Oj::StringWriter)
        expect(second).to be_a(Oj::StringWriter)
      end
    end

    describe "#checkin" do
      it "leaves exactly N Writers in the stack after N checkouts followed by N checkins" do
        n = 4
        writers = Array.new(n) { pool.checkout }
        writers.each { |w| pool.checkin(w) }

        expect(pool.send(:storage).size).to eq(n)
      end

      it "clears the Writer's buffer so the next checkout sees an empty to_s" do
        writer = pool.checkout
        writer.push_object
        writer.push_value(1, "id")
        writer.pop
        pool.checkin(writer)

        reused = pool.checkout
        expect(reused).to equal(writer)
        expect(reused.to_s).to eq("")
      end
    end

    describe "no-leak regression at depth 1" do
      it "produces a steady-state pool size of exactly 1 across 10_000 serial cycles" do
        10_000.times do
          w = pool.checkout
          pool.checkin(w)
        end

        expect(pool.send(:storage).size).to eq(1)
      end

      it "calls Oj::StringWriter.new exactly once across 10_000 serial cycles" do
        call_count = 0
        original = Oj::StringWriter.method(:new)
        allow(Oj::StringWriter).to receive(:new) do |*args, **kwargs|
          call_count += 1
          original.call(*args, **kwargs)
        end

        10_000.times do
          w = pool.checkout
          pool.checkin(w)
        end

        expect(call_count).to eq(1)
      end
    end

    describe "no-leak regression at depth 2" do
      it "produces a steady-state pool size of exactly 2 across 10_000 reentrant cycles" do
        10_000.times do
          a = pool.checkout
          b = pool.checkout
          pool.checkin(b)
          pool.checkin(a)
        end

        expect(pool.send(:storage).size).to eq(2)
      end

      it "calls Oj::StringWriter.new exactly twice across 10_000 reentrant cycles" do
        call_count = 0
        original = Oj::StringWriter.method(:new)
        allow(Oj::StringWriter).to receive(:new) do |*args, **kwargs|
          call_count += 1
          original.call(*args, **kwargs)
        end

        10_000.times do
          a = pool.checkout
          b = pool.checkout
          pool.checkin(b)
          pool.checkin(a)
        end

        expect(call_count).to eq(2)
      end
    end

    describe "exception recovery via begin/ensure" do
      it "returns the Writer to the stack cleared even when the body raises" do
        writer_seen = nil

        expect {
          writer = pool.checkout
          writer_seen = writer
          begin
            writer.push_object
            writer.push_value(1, "id")
            raise "boom"
          ensure
            pool.checkin(writer)
          end
        }.to raise_error("boom")

        # Stack now holds the same writer, cleared.
        expect(pool.send(:storage).size).to eq(1)
        reused = pool.checkout
        expect(reused).to equal(writer_seen)
        expect(reused.to_s).to eq("")
      end
    end

    describe "fiber-local isolation (Thread#[] is fiber-local per MRI thread.c:3812)" do
      it "hands out distinct Writers to two Fibers checking out before any checkin" do
        ids = []
        f_a = Fiber.new do
          w = pool.checkout
          ids << w.object_id
          Fiber.yield
        end
        f_b = Fiber.new do
          w = pool.checkout
          ids << w.object_id
        end

        f_a.resume
        f_b.resume
        f_a.resume

        expect(ids.size).to eq(2)
        expect(ids.first).not_to eq(ids.last)
      end
    end
  end

  describe SerializersCodeGen::WritersPool::IsolatedExecutionState do
    subject(:pool) { described_class.new(storage_key) }

    let(:storage_key) { :"_scg_writer_ies_test_#{object_id}" }

    around do |example|
      skip "ActiveSupport::IsolatedExecutionState not loaded" unless defined?(ActiveSupport::IsolatedExecutionState)
      example.run
    ensure
      ActiveSupport::IsolatedExecutionState.delete(storage_key) if defined?(ActiveSupport::IsolatedExecutionState)
    end

    it "allocates a fresh Oj::StringWriter when the stack is empty" do
      writer = pool.checkout

      expect(writer).to be_a(Oj::StringWriter)
    end

    it "reuses the same Oj::StringWriter instance after checkin" do
      first = pool.checkout
      pool.checkin(first)
      second = pool.checkout

      expect(second).to equal(first)
    end

    it "isolates checkouts across Fibers when AS::IES isolation_level is :fiber" do
      prior = ActiveSupport::IsolatedExecutionState.isolation_level
      ActiveSupport::IsolatedExecutionState.isolation_level = :fiber
      ids = []
      begin
        f_a = Fiber.new do
          w = pool.checkout
          ids << w.object_id
          Fiber.yield
        end
        f_b = Fiber.new do
          w = pool.checkout
          ids << w.object_id
        end

        f_a.resume
        f_b.resume
        f_a.resume

        expect(ids.size).to eq(2)
        expect(ids.first).not_to eq(ids.last)
      ensure
        ActiveSupport::IsolatedExecutionState.isolation_level = prior
      end
    end
  end
end
