# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

RSpec.describe "parent_class dispatch - Symbol-body Method Attribute contract" do
  def attribute(name, source = name)
    Panko::CodeGen::Attribute.new(name: name, source: source)
  end

  def method_attribute(name, body)
    Panko::CodeGen::MethodAttribute.new(name: name, body: body)
  end

  def descriptor_with(name:, parent_class:, attributes: [], method_attributes: [], associations: [], model: nil)
    Panko::CodeGen::Descriptor.new(
      name: name,
      model: model,
      parent_class: parent_class,
      attributes: attributes,
      method_attributes: method_attributes,
      associations: associations
    )
  end

  def compile(descriptor, mode)
    Panko::CodeGen.compile(descriptor, output: mode).new(descriptor: descriptor)
  end

  describe "(1) Symbol-body resolves via direct method dispatch on self - basic correctness" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "calls the named method on the Generated Class instance (inherited from parent_class)" do
          stub_const("ParentClassDispatchSpec_Basic", Class.new {
            def make_greeting
              "hello world"
            end
          })

          descriptor = descriptor_with(
            name: "ParentClassDispatchSpec_BasicSerializer_#{mode}",
            parent_class: ParentClassDispatchSpec_Basic,
            attributes: [attribute(:id)],
            method_attributes: [method_attribute(:greeting, :make_greeting)]
          )
          generated = compile(descriptor, mode)
          result = generated.serialize_one({"id" => 1})
          parsed = (mode == :json) ? Oj.load(result) : result
          expect(parsed).to eq("id" => 1, "greeting" => "hello world")
        end
      end
    end
  end

  describe "(2) @object / @context / @scope populated for user code reading them" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "exposes the per-record ivars on self before the Symbol-body method dispatches" do
          stub_const("ParentClassDispatchSpec_Ivars", Class.new {
            def tag
              "object=#{@object["name"]}|context=#{@context}|scope=#{@scope}"
            end
          })

          descriptor = descriptor_with(
            name: "ParentClassDispatchSpec_IvarsSerializer_#{mode}",
            parent_class: ParentClassDispatchSpec_Ivars,
            attributes: [attribute(:name)],
            method_attributes: [method_attribute(:tag, :tag)]
          )
          generated = compile(descriptor, mode)
          result = generated.serialize_one({"name" => "alice"}, context: "env1", scope: "v1")
          parsed = (mode == :json) ? Oj.load(result) : result
          expect(parsed).to eq("name" => "alice", "tag" => "object=alice|context=env1|scope=v1")
        end
      end
    end
  end

  describe "(3) Callable-body and Symbol-body coexist in the same Descriptor" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "calls the Symbol via direct dispatch and the Callable via @cb_<name>.call(...) in one Generated Class" do
          stub_const("ParentClassDispatchSpec_Mixed", Class.new {
            def shouty_name
              @object["name"].upcase
            end
          })

          descriptor = descriptor_with(
            name: "ParentClassDispatchSpec_MixedSerializer_#{mode}",
            parent_class: ParentClassDispatchSpec_Mixed,
            attributes: [attribute(:id)],
            method_attributes: [
              method_attribute(:shouty_name, :shouty_name),
              method_attribute(:static, -> { 42 }),
              method_attribute(:context_tag, ->(_record, context) { "ctx=#{context}" })
            ]
          )
          generated = compile(descriptor, mode)
          result = generated.serialize_one({"id" => 1, "name" => "alice"}, context: "env")
          parsed = (mode == :json) ? Oj.load(result) : result
          expect(parsed).to eq(
            "id" => 1,
            "shouty_name" => "ALICE",
            "static" => 42,
            "context_tag" => "ctx=env"
          )
        end
      end
    end
  end

  describe "(4) super works from a Symbol-body method - parent-class hierarchy compat" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "resolves super up the user-defined class hierarchy" do
          stub_const("ParentClassDispatchSpec_SuperGrand", Class.new {
            def greeting
              "Hi"
            end
          })
          stub_const("ParentClassDispatchSpec_SuperParent", Class.new(ParentClassDispatchSpec_SuperGrand) {
            def greeting
              "#{super}, #{@object["name"]}!"
            end
          })

          descriptor = descriptor_with(
            name: "ParentClassDispatchSpec_SuperSerializer_#{mode}",
            parent_class: ParentClassDispatchSpec_SuperParent,
            attributes: [attribute(:id)],
            method_attributes: [method_attribute(:greeting, :greeting)]
          )
          generated = compile(descriptor, mode)
          result = generated.serialize_one({"id" => 1, "name" => "alice"})
          parsed = (mode == :json) ? Oj.load(result) : result
          expect(parsed).to eq("id" => 1, "greeting" => "Hi, alice!")
        end
      end
    end
  end

  describe "(5) private method on parent_class callable as Symbol-body - private-dispatch compat" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "invokes the private method via no-explicit-receiver dispatch on self" do
          stub_const("ParentClassDispatchSpec_Private", Class.new {
            private def secret_tag
              "secret:#{@object["name"]}"
            end
          })

          descriptor = descriptor_with(
            name: "ParentClassDispatchSpec_PrivateSerializer_#{mode}",
            parent_class: ParentClassDispatchSpec_Private,
            attributes: [attribute(:id)],
            method_attributes: [method_attribute(:secret_tag, :secret_tag)]
          )
          generated = compile(descriptor, mode)
          result = generated.serialize_one({"id" => 1, "name" => "alice"})
          parsed = (mode == :json) ? Oj.load(result) : result
          expect(parsed).to eq("id" => 1, "secret_tag" => "secret:alice")
        end
      end
    end
  end

  describe "(6) prepend-ed module method overrides parent's method - prepend compat" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "dispatches through the prepended module before the parent's own method" do
          stub_const("ParentClassDispatchSpec_PrependBase", Class.new {
            def greeting
              "Base"
            end
          })
          prepender = Module.new do
            def greeting
              "Wrapped(#{super})"
            end
          end
          ParentClassDispatchSpec_PrependBase.prepend(prepender)

          descriptor = descriptor_with(
            name: "ParentClassDispatchSpec_PrependSerializer_#{mode}",
            parent_class: ParentClassDispatchSpec_PrependBase,
            attributes: [attribute(:id)],
            method_attributes: [method_attribute(:greeting, :greeting)]
          )
          generated = compile(descriptor, mode)
          result = generated.serialize_one({"id" => 1})
          parsed = (mode == :json) ? Oj.load(result) : result
          expect(parsed).to eq("id" => 1, "greeting" => "Wrapped(Base)")
        end
      end
    end
  end

  describe "(7) Helper methods called from a Symbol-body see the same @object - helper-method chain" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "threads @object through nested method calls within one _write_one / _to_hash frame" do
          stub_const("ParentClassDispatchSpec_Helpers", Class.new {
            def tag
              "id=#{record_id}|name=#{record_name}"
            end

            def record_id
              @object["id"]
            end

            def record_name
              @object["name"]
            end
          })

          descriptor = descriptor_with(
            name: "ParentClassDispatchSpec_HelpersSerializer_#{mode}",
            parent_class: ParentClassDispatchSpec_Helpers,
            attributes: [attribute(:id)],
            method_attributes: [method_attribute(:tag, :tag)]
          )
          generated = compile(descriptor, mode)
          result = generated.serialize_one({"id" => 7, "name" => "alice"})
          parsed = (mode == :json) ? Oj.load(result) : result
          expect(parsed).to eq("id" => 7, "tag" => "id=7|name=alice")
        end
      end
    end
  end

  describe "(8) Self-recursion: each nested Generated Class frame sees its own @object / @context / @scope" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        # One instance serves every depth (@replies_serializer = self), and each _write_one / _to_hash
        # entry writes @object / @context / @scope. Only leaves are checked: no nested call runs before their tag.
        it "each leaf frame's Symbol-body method reads its own @object / @context / @scope" do
          stub_const("ParentClassDispatchSpec_RecursiveBase", Class.new {
            def tag
              "id=#{@object["id"]}|ctx=#{@context}|scope=#{@scope}"
            end
          })

          comment = Panko::CodeGen::Descriptor.new(
            name: "ParentClassDispatchSpec_RecursiveSerializer_#{mode}",
            model: nil,
            parent_class: ParentClassDispatchSpec_RecursiveBase,
            attributes: [attribute(:id)],
            method_attributes: [method_attribute(:tag, :tag)],
            associations: []
          )
          comment.associations << Panko::CodeGen::Association.new(
            name: :replies, kind: :has_many, descriptor: comment
          )
          generated = compile(comment, mode)
          record = {
            "id" => 1,
            "replies" => [
              {"id" => 2, "replies" => []},
              {"id" => 3, "replies" => []}
            ]
          }
          result = generated.serialize_one(record, context: "env1", scope: "alice")
          parsed = (mode == :json) ? Oj.load(result) : result
          expect(parsed["replies"][0]).to eq(
            "id" => 2, "replies" => [], "tag" => "id=2|ctx=env1|scope=alice"
          )
          expect(parsed["replies"][1]).to eq(
            "id" => 3, "replies" => [], "tag" => "id=3|ctx=env1|scope=alice"
          )
        end
      end
    end
  end

  describe "(9) Symbol resolving to a non-existent method raises Ruby's NameError at serialize time" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "raises NameError at serialize_one time, not at Compile time" do
          stub_const("ParentClassDispatchSpec_MissingMethodBase", Class.new {
          })

          descriptor = descriptor_with(
            name: "ParentClassDispatchSpec_MissingMethodSerializer_#{mode}",
            parent_class: ParentClassDispatchSpec_MissingMethodBase,
            attributes: [attribute(:id)],
            method_attributes: [method_attribute(:greeting, :nonexistent)]
          )

          generated = nil
          expect { generated = compile(descriptor, mode) }.not_to raise_error
          expect { generated.serialize_one({"id" => 1}) }.to raise_error(NameError, /nonexistent/)
        end
      end
    end
  end
end
