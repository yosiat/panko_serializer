# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

# Narrow emit-shape tests for the S18.3 +parent_class+ dispatch wiring:
# the +FieldEmitters::MethodAttribute+ Symbol-vs-Callable branch and the
# per-record +@object+ / +@context+ / +@scope+ ivar writes prepended at
# the +RecordAccess+ dispatch sites when +descriptor.parent_class+ is
# non-+nil+. These assert directly on the +Generator+'s source-string
# output — no +module_eval+, no snapshot files. The full snapshot tier +
# end-to-end concern spec land in S18.4 once the three
# +parent_class_*+ fixtures land.
#
# The +parent_class: nil+ default stays byte-identical to pre-S18 emit;
# the existing 17+17 snapshots under +spec/fixtures/generated/+ remain
# the source of truth for that property — here we just pin that flipping
# +parent_class:+ to a +Class+ flips on the ivar writes and the
# Symbol-body branch leaves no +@cb_<name>+ traces.
RSpec.describe "Generator parent_class dispatch emit (S18.3)" do
  let(:generator) { Panko::CodeGen::Generator.new }
  let(:config) { Panko::CodeGen::Config.new }
  let(:parent_class) {
    parent = Class.new
    stub_const("ParentClassDispatchSpecBase", parent)
    parent
  }

  describe "FieldEmitters::MethodAttribute Symbol-vs-Callable branch" do
    let(:descriptor) {
      Panko::CodeGen::Descriptor.new(
        name: "MixedBodySerializer",
        models: nil,
        attributes: [],
        method_attributes: [
          Panko::CodeGen::MethodAttribute.new(name: :static_via_callable, body: -> { 1 }),
          Panko::CodeGen::MethodAttribute.new(name: :greeting, body: :greeting)
        ],
        associations: [],
        parent_class: parent_class
      )
    }

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "emits +value = <method_name>+ for Symbol bodies, not +@cb_<name>.call+" do
          source = generator.emit(descriptor, output: mode, config: config)
          expect(source).to include("value = greeting\n")
          expect(source).not_to include("@cb_greeting.call")
        end

        it "still emits the arity-specialized +@cb_<name>.call+ for Callable bodies" do
          source = generator.emit(descriptor, output: mode, config: config)
          expect(source).to include("value = @cb_static_via_callable.call\n")
        end

        it "does not hoist +@cb_<symbol_name>+ in the constructor (only Callable bodies are hoisted)" do
          source = generator.emit(descriptor, output: mode, config: config)
          expect(source).to include("@cb_static_via_callable = descriptor.method_attributes[0].body")
          expect(source).not_to include("@cb_greeting = descriptor.method_attributes[1].body")
          expect(source).not_to include("@cb_greeting =")
        end
      end
    end
  end

  describe "per-record ivar writes on Specialized path" do
    let(:descriptor) {
      Panko::CodeGen::Descriptor.new(
        name: "SpecializedParentSerializer",
        models: [Post],
        attributes: [Panko::CodeGen::Attribute.new(name: :id)],
        method_attributes: [],
        associations: [],
        parent_class: parent_class
      )
    }

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:entry_method) { (mode == :json) ? "_write_one(record, writer, context, scope, filters)" : "_to_hash(record, context, scope, filters)" }

        it "prepends @object/@context/@scope writes at the top of the body" do
          source = generator.emit(descriptor, output: mode, config: config)
          expected_block =
            "  def #{entry_method}\n" \
            "    @object = record\n" \
            "    @context = context\n" \
            "    @scope = scope\n"
          expect(source).to include(expected_block)
        end
      end
    end
  end

  describe "per-record ivar writes on Generic path — dispatchers only" do
    let(:descriptor) {
      Panko::CodeGen::Descriptor.new(
        name: "GenericParentSerializer",
        models: nil,
        attributes: [Panko::CodeGen::Attribute.new(name: :id)],
        method_attributes: [],
        associations: [],
        parent_class: parent_class
      )
    }

    context "with json Output Mode" do
      it "prepends ivar writes at the top of the _write_one dispatcher" do
        source = generator.emit(descriptor, output: :json, config: config)
        expected =
          "  def _write_one(record, writer, context, scope, filters)\n" \
          "    @object = record\n" \
          "    @context = context\n" \
          "    @scope = scope\n" \
          "    if record.is_a?(Hash)\n"
        expect(source).to include(expected)
      end

      it "leaves the _write_one_hash / _write_one_object helpers unprepended" do
        source = generator.emit(descriptor, output: :json, config: config)
        expected_hash_helper =
          "  def _write_one_hash(record, writer, context, scope, filters)\n" \
          "    writer.push_object\n"
        expected_object_helper =
          "  def _write_one_object(record, writer, context, scope, filters)\n" \
          "    writer.push_object\n"
        expect(source).to include(expected_hash_helper)
        expect(source).to include(expected_object_helper)
      end
    end

    context "with hash Output Mode" do
      it "prepends ivar writes at the top of the _to_hash dispatcher" do
        source = generator.emit(descriptor, output: :hash, config: config)
        expected =
          "  def _to_hash(record, context, scope, filters)\n" \
          "    @object = record\n" \
          "    @context = context\n" \
          "    @scope = scope\n" \
          "    if record.is_a?(Hash)\n"
        expect(source).to include(expected)
      end

      it "leaves the _to_hash_hash / _to_hash_object helpers unprepended" do
        source = generator.emit(descriptor, output: :hash, config: config)
        expected_hash_helper =
          "  def _to_hash_hash(record, context, scope, filters)\n" \
          "    result = {}\n"
        expected_object_helper =
          "  def _to_hash_object(record, context, scope, filters)\n" \
          "    result = {}\n"
        expect(source).to include(expected_hash_helper)
        expect(source).to include(expected_object_helper)
      end
    end
  end

  describe "parent_class: nil — no ivar writes prepended (byte-identical to pre-S18)" do
    let(:specialized_descriptor) {
      Panko::CodeGen::Descriptor.new(
        name: "NoParentSpecializedSerializer",
        models: [Post],
        attributes: [Panko::CodeGen::Attribute.new(name: :id)],
        method_attributes: [],
        associations: []
      )
    }
    let(:generic_descriptor) {
      Panko::CodeGen::Descriptor.new(
        name: "NoParentGenericSerializer",
        models: nil,
        attributes: [Panko::CodeGen::Attribute.new(name: :id)],
        method_attributes: [],
        associations: []
      )
    }

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode (Specialized)" do
        it "emits no @object/@context/@scope writes" do
          source = generator.emit(specialized_descriptor, output: mode, config: config)
          expect(source).not_to include("@object = record")
          expect(source).not_to include("@context = context")
          expect(source).not_to include("@scope = scope")
        end
      end

      context "with #{mode} Output Mode (Generic)" do
        it "emits no @object/@context/@scope writes" do
          source = generator.emit(generic_descriptor, output: mode, config: config)
          expect(source).not_to include("@object = record")
          expect(source).not_to include("@context = context")
          expect(source).not_to include("@scope = scope")
        end
      end
    end
  end

  describe "end-to-end compile + serialize via native Ruby dispatch" do
    # The S18.2 validator widening (CallableArity Symbol-skip) ships in a
    # parallel slice (#97); until it lands, +Validator+'s default chain
    # calls +Symbol#arity+ which raises +NoMethodError+. The
    # +rules: []+ escape hatch on +Validator.new+ (documented as a
    # test-affordance in +Validators::Validator+) routes around that
    # without coupling this slice to the validator slice.
    let(:parent_class_with_methods) {
      parent = Class.new do
        def greeting
          "Hi #{@object["name"]}"
        end

        def ctx_label
          "ctx=#{@context}"
        end

        def scope_label
          "scope=#{@scope}"
        end
      end
      stub_const("ParentClassDispatchEndToEndBase", parent)
      parent
    }
    let(:descriptor) {
      Panko::CodeGen::Descriptor.new(
        name: "SymbolBodyEndToEndSerializer",
        models: nil,
        attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
        method_attributes: [
          Panko::CodeGen::MethodAttribute.new(name: :static, body: -> { 99 }),
          Panko::CodeGen::MethodAttribute.new(name: :greeting, body: :greeting),
          Panko::CodeGen::MethodAttribute.new(name: :ctx_label, body: :ctx_label),
          Panko::CodeGen::MethodAttribute.new(name: :scope_label, body: :scope_label)
        ],
        associations: [],
        parent_class: parent_class_with_methods
      )
    }

    def compile(descriptor, mode)
      Panko::CodeGen::Compiler.new(
        descriptor,
        output: mode,
        config: config,
        validator: Panko::CodeGen::Validators::Validator.new(rules: [])
      ).compile
    end

    it "dispatches a Symbol-body to a method on self (JSON)" do
      generated = compile(descriptor, :json).new(descriptor: descriptor)
      record = {"id" => 1, "name" => "Ada"}
      result = JSON.parse(generated.serialize_one(record, context: "C", scope: "S"))
      expect(result).to eq(
        "id" => 1,
        "static" => 99,
        "greeting" => "Hi Ada",
        "ctx_label" => "ctx=C",
        "scope_label" => "scope=S"
      )
    end

    it "dispatches a Symbol-body to a method on self (Hash)" do
      generated = compile(descriptor, :hash).new(descriptor: descriptor)
      record = {"id" => 1, "name" => "Ada"}
      result = generated.serialize_one(record, context: "C", scope: "S")
      expect(result).to eq(
        "id" => 1,
        "static" => 99,
        "greeting" => "Hi Ada",
        "ctx_label" => "ctx=C",
        "scope_label" => "scope=S"
      )
    end

    it "raises Ruby's native error at serialize time for a Symbol resolving to a missing method" do
      # Ruby raises +NameError+ (which is +NoMethodError+'s superclass)
      # for a bare-identifier reference that resolves to neither a
      # local variable nor a method on +self+; +NoMethodError+ fires
      # only for explicit-receiver dispatch (+self.foo+). The emitted
      # shape is bare per the PRD (+value = <method_name>+), so the
      # natural Ruby class here is +NameError+. The contract that
      # matters is "no scg-specific error" + "no Compile-time check"
      # — both pinned here; the runtime error stays Ruby-native.
      descriptor_missing = Panko::CodeGen::Descriptor.new(
        name: "MissingMethodSerializer",
        models: nil,
        attributes: [],
        method_attributes: [
          Panko::CodeGen::MethodAttribute.new(name: :nope, body: :nope_does_not_exist)
        ],
        associations: [],
        parent_class: parent_class_with_methods
      )
      generated = compile(descriptor_missing, :json).new(descriptor: descriptor_missing)
      expect {
        generated.serialize_one({})
      }.to raise_error(NameError, /nope_does_not_exist/)
    end
  end
end
