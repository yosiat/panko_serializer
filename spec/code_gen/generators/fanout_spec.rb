# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

# Unit-tier coverage for the file-list shape +Generators::Fanout+
# returns. The end-to-end on-disk wiring is covered by
# +spec/features/dump_fan_out_spec.rb+ + the snapshot tier; this spec
# pins the +require_relative+ deduplication, self-loop suppression,
# and post-order guarantees on edge-case Descriptor shapes the
# fixture corpus does not exercise.
RSpec.describe Panko::CodeGen::Generators::Fanout do
  def descriptor(name, associations: [])
    Panko::CodeGen::Descriptor.new(
      name: name, model: nil,
      attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [], associations: associations
    )
  end

  def has_one(target, name:)
    Panko::CodeGen::Association.new(name: name, kind: :has_one, descriptor: target)
  end

  let(:config) { Panko::CodeGen::Config.new }

  describe ".basename_for" do
    it "snake_cases the Descriptor name and joins it to the Output Mode + .rb" do
      d = descriptor("PostSerializer")
      expect(described_class.basename_for(d, :json)).to eq("post_serializer_json.rb")
      expect(described_class.basename_for(d, :hash)).to eq("post_serializer_hash.rb")
    end
  end

  describe ".emit_files" do
    it "emits one file per unique Descriptor in tree post-order (children before parents)" do
      inner = descriptor("Inner")
      outer = descriptor("Outer", associations: [has_one(inner, name: :inner)])
      files = described_class.emit_files(outer, output: :json, config: config)
      expect(files.map { |f| f[:descriptor] }).to eq([inner, outer])
    end

    it "emits exactly one require_relative per unique target even when two Associations share it" do
      inner = descriptor("SharedInner")
      outer = descriptor("OuterWithShared", associations: [
        has_one(inner, name: :first),
        has_one(inner, name: :second)
      ])
      files = described_class.emit_files(outer, output: :json, config: config)
      outer_source = files.find { |f| f[:descriptor].equal?(outer) }[:source]
      expect(outer_source.scan(/^require_relative "shared_inner_json"$/).size).to eq(1)
    end

    it "emits no require_relative directives for a self-loop (handled by @<n>_serializer = self)" do
      d = descriptor("Recur")
      d.associations << has_one(d, name: :parent)
      files = described_class.emit_files(d, output: :json, config: config)
      expect(files.size).to eq(1)
      expect(files.first[:source]).not_to match(/^require_relative\b/)
    end

    it "preserves Association declaration order for require_relative directives" do
      a = descriptor("A")
      b = descriptor("B")
      c = descriptor("C")
      outer = descriptor("Outer", associations: [
        has_one(b, name: :b_first),
        has_one(c, name: :c_second),
        has_one(a, name: :a_third)
      ])
      files = described_class.emit_files(outer, output: :json, config: config)
      outer_source = files.find { |f| f[:descriptor].equal?(outer) }[:source]
      requires = outer_source.each_line.grep(/^require_relative\b/).map(&:strip)
      expect(requires).to eq([
        %(require_relative "b_json"),
        %(require_relative "c_json"),
        %(require_relative "a_json")
      ])
    end

    it "puts the # frozen_string_literal: true pragma at line 1 of every file" do
      inner = descriptor("Inner")
      outer = descriptor("Outer", associations: [has_one(inner, name: :inner)])
      files = described_class.emit_files(outer, output: :hash, config: config)
      files.each do |file|
        expect(file[:source].lines.first).to eq("# frozen_string_literal: true\n")
      end
    end
  end
end
