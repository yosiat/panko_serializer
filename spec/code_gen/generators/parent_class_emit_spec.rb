# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

# Narrow emit-shape tests for the S18.1 +Descriptor#parent_class+ parent
# swap in +ClassEmitter#emit_class+. These assert
# directly on the +Generator+'s source-string output — no +module_eval+,
# no snapshot files. The full snapshot tier picks up the long-form
# coverage in S18.4 once the +parent_class_specialized+ /
# +parent_class_generic+ fixtures land.
#
# The +parent_class: nil+ default is already pinned byte-identical by
# every existing snapshot under +spec/fixtures/generated/+; here we just
# pin that flipping +parent_class:+ to a +Class+ swaps the +class <Name>_<Mode>+
# line into +class <Name>_<Mode> < <ParentClass>+ and leaves every other
# byte alone.
RSpec.describe "Generator parent_class emit (S18.1)" do
  let(:generator) { Panko::CodeGen::Generator.new }
  let(:config) { Panko::CodeGen::Config.new }
  let(:parent_class) {
    parent = Class.new
    stub_const("ParentClassEmitSpecBase", parent)
    parent
  }

  def descriptor(parent_class:)
    Panko::CodeGen::Descriptor.new(
      name: "DemoSerializer",
      model: nil,
      attributes: [Panko::CodeGen::Attribute.new(name: :id)],
      method_attributes: [],
      associations: [],
      parent_class: parent_class
    )
  end

  %i[json hash].each do |mode|
    context "with #{mode} Output Mode" do
      let(:suffix) { (mode == :json) ? "JSON" : "Hash" }

      it "emits the bare class line when parent_class is nil" do
        source = generator.emit(descriptor(parent_class: nil), output: mode, config: config)
        expect(source).to include("class DemoSerializer_#{suffix}\n")
        expect(source).not_to include("class DemoSerializer_#{suffix} <")
      end

      it "emits the subclass line when parent_class is a Class" do
        source = generator.emit(descriptor(parent_class: parent_class), output: mode, config: config)
        expect(source).to include("class DemoSerializer_#{suffix} < ParentClassEmitSpecBase\n")
      end

      it "uses parent_class.name verbatim (fully-qualified) for namespaced parents" do
        namespaced_parent = Class.new
        stub_const("Outer::Inner::CustomBase", namespaced_parent)
        source = generator.emit(descriptor(parent_class: namespaced_parent), output: mode, config: config)
        expect(source).to include("class DemoSerializer_#{suffix} < Outer::Inner::CustomBase\n")
      end
    end
  end

  describe "compiled superclass identity" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:suffix) { (mode == :json) ? "JSON" : "Hash" }

        it "produces a Generated Class whose .superclass == the supplied parent_class" do
          parent = Class.new
          stub_const("ParentClassIdentitySpecBase_#{suffix}", parent)
          desc = Panko::CodeGen::Descriptor.new(
            name: "ParentClassIdentitySerializer_#{suffix}",
            model: nil,
            attributes: [Panko::CodeGen::Attribute.new(name: :id)],
            method_attributes: [],
            associations: [],
            parent_class: parent
          )
          generated = Panko::CodeGen.compile(desc, output: mode)
          expect(generated.superclass).to equal(parent)
        end

        it "defaults to Object as the superclass when parent_class is nil" do
          desc = Panko::CodeGen::Descriptor.new(
            name: "DefaultSuperSerializer_#{suffix}",
            model: nil,
            attributes: [Panko::CodeGen::Attribute.new(name: :id)],
            method_attributes: [],
            associations: []
          )
          generated = Panko::CodeGen.compile(desc, output: mode)
          expect(generated.superclass).to equal(Object)
        end
      end
    end
  end
end
