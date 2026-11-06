# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen/writers_pool"

RSpec.describe Panko::CodeGen::WritersPool do
  describe "abstract base" do
    it "raises NotImplementedError on checkout, since #storage is unimplemented" do
      expect { described_class.new(:_panko_writer_abstract_base_test).checkout }
        .to raise_error(NotImplementedError, /must override #storage/)
    end
  end

  describe Panko::CodeGen::WritersPool::ThreadLocal do
    subject(:pool) { described_class.new(storage_key) }

    let(:storage_key) { :"_panko_writer_test_#{object_id}" }

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
      # A globally-shared storage would fail this test: Fiber A's checked-in
      # writer would sit in the shared stack and Fiber B's checkout would
      # pop it, returning the same instance. Fiber-local storage isolates
      # the stacks, so Fiber B finds an empty stack and allocates fresh.
      it "does not surface a Fiber's checked-in Writer to a sibling Fiber's checkout" do
        a_writer = nil
        b_writer = nil

        f_a = Fiber.new do
          a_writer = pool.checkout
          pool.checkin(a_writer)
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
    subject(:pool) { described_class.new(storage_key) }

    let(:storage_key) { :"_panko_writer_ies_test_#{object_id}" }

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

    # Mirror of the ThreadLocal locality test: with isolation_level: :fiber,
    # AS::IES is fiber-local, so a checkin in Fiber A must not surface to a
    # checkout in Fiber B. A non-fiber-local backend would pop A's writer.
    it "does not surface a Fiber's checked-in Writer to a sibling Fiber when isolation_level is :fiber" do
      prior = ActiveSupport::IsolatedExecutionState.isolation_level
      ActiveSupport::IsolatedExecutionState.isolation_level = :fiber
      a_writer = nil
      b_writer = nil
      begin
        f_a = Fiber.new do
          a_writer = pool.checkout
          pool.checkin(a_writer)
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
