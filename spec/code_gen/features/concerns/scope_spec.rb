# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"

# Cross-cutting +Scope+ threading contract — the 9-item enumeration
# (S17.3 / PRD #89). JSON/Hash
# parity is iterated at the +describe+ block (this is item (9) and pins
# the parallel emit shapes). Fixtures are inline
# minimal Descriptors; the +scope_threading+ canonical fixture from
# S17.2 / #91 pins the emit bytes at the snapshot tier — this file pins
# the runtime semantics: what arity-3 Callables observe and what
# +serialize_one+ / +serialize_many+ produce when +scope:+ and +context:+
# are threaded through Composition.
RSpec.describe "Scope — threading contract for Method Attribute and Association if: Callables" do
  def descriptor_with(name: "ScopeDescriptor", attributes: [], method_attributes: [], associations: [])
    Panko::CodeGen::Descriptor.new(
      name: name,
      model: nil,
      parent_class: Fixtures::BaseSerializer,
      attributes: attributes,
      method_attributes: method_attributes,
      associations: associations
    )
  end

  def attribute(name)
    Panko::CodeGen::Attribute.new(name: name)
  end

  def method_attribute(name, body)
    Panko::CodeGen::MethodAttribute.new(name: name, body: body)
  end

  def has_one(name = :child, descriptor:, if: nil)
    Panko::CodeGen::Association.new(
      name: name, kind: :has_one, descriptor: descriptor, if: binding.local_variable_get(:if)
    )
  end

  def has_many(name = :children, descriptor:, if: nil)
    Panko::CodeGen::Association.new(
      name: name, kind: :has_many, descriptor: descriptor, if: binding.local_variable_get(:if)
    )
  end

  def compile(descriptor, mode)
    Panko::CodeGen.compile(descriptor, output: mode).new(descriptor: descriptor)
  end

  describe "(1) scope: defaults to nil when omitted at serialize_one / serialize_many" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "passes nil to an arity-3 Method Attribute Callable for serialize_one" do
          captured = :unset
          body = ->(_record, _context, scope) {
            captured = scope
            "ok"
          }
          descriptor = descriptor_with(method_attributes: [method_attribute(:tag, body)])
          generated = compile(descriptor, mode)
          generated.serialize_one({"id" => 1})
          expect(captured).to be_nil
        end

        it "passes nil to an arity-3 Method Attribute Callable for serialize_many" do
          observed = []
          body = ->(_record, _context, scope) {
            observed << scope
            "ok"
          }
          descriptor = descriptor_with(method_attributes: [method_attribute(:tag, body)])
          generated = compile(descriptor, mode)
          generated.serialize_many([{"id" => 1}, {"id" => 2}])
          expect(observed).to eq([nil, nil])
        end
      end
    end
  end

  describe "(2) scope is distinct from context — arity-3 Callable observes them as (record, context, scope)" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "passes record, context, scope positionally — different identities preserved" do
          captured_record = nil
          captured_context = nil
          captured_scope = nil
          body = ->(record, context, scope) {
            captured_record = record
            captured_context = context
            captured_scope = scope
            "ok"
          }
          descriptor = descriptor_with(method_attributes: [method_attribute(:tag, body)])
          generated = compile(descriptor, mode)
          record = {"id" => 1}
          context = Object.new
          scope = Object.new
          generated.serialize_one(record, context: context, scope: scope)
          expect(captured_record).to equal(record)
          expect(captured_context).to equal(context)
          expect(captured_scope).to equal(scope)
        end
      end
    end
  end

  describe "(3) arity-2 Callables ignore scope — no leak" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "invokes a strict 2-arity Lambda with (record, context) when scope: is passed" do
          captured_record = nil
          captured_context = nil
          # Lambdas strictly enforce arity — if scope leaked in as a third
          # positional, this would raise ArgumentError at call time.
          body = ->(record, context) {
            captured_record = record
            captured_context = context
            "ok"
          }
          expect(body.arity).to eq(2)
          descriptor = descriptor_with(method_attributes: [method_attribute(:legacy, body)])
          generated = compile(descriptor, mode)
          record = {"id" => 1}
          context = Object.new
          scope = Object.new
          expect {
            generated.serialize_one(record, context: context, scope: scope)
          }.not_to raise_error
          expect(captured_record).to equal(record)
          expect(captured_context).to equal(context)
        end
      end
    end
  end

  describe "(4) scope threads unchanged into nested has_one" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "the inner Method Attribute observes the same scope identity (equal?) as the outer" do
          outer_scope = nil
          inner_scope = nil
          outer_body = ->(_record, _context, scope) {
            outer_scope = scope
            "outer"
          }
          inner_body = ->(_record, _context, scope) {
            inner_scope = scope
            "inner"
          }
          inner = descriptor_with(
            name: "ScopeInnerSerializer",
            attributes: [attribute(:id)],
            method_attributes: [method_attribute(:inner_tag, inner_body)]
          )
          outer = descriptor_with(
            name: "ScopeOuterSerializer",
            attributes: [attribute(:id)],
            method_attributes: [method_attribute(:outer_tag, outer_body)],
            associations: [has_one(:child, descriptor: inner)]
          )
          generated = compile(outer, mode)
          scope = Object.new
          generated.serialize_one(
            {"id" => 1, "child" => {"id" => 7}},
            scope: scope
          )
          expect(outer_scope).to equal(scope)
          expect(inner_scope).to equal(scope)
        end
      end
    end
  end

  describe "(5) scope threads unchanged into nested has_many" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "each element's inner Method Attribute observes the same scope identity (equal?)" do
          observed_scopes = []
          inner_body = ->(_record, _context, scope) {
            observed_scopes << scope
            "ok"
          }
          inner = descriptor_with(
            name: "ScopeManyInnerSerializer",
            attributes: [attribute(:id)],
            method_attributes: [method_attribute(:tag, inner_body)]
          )
          outer = descriptor_with(
            name: "ScopeManyOuterSerializer",
            attributes: [attribute(:id)],
            associations: [has_many(:children, descriptor: inner)]
          )
          generated = compile(outer, mode)
          scope = Object.new
          generated.serialize_one(
            {"id" => 1, "children" => [{"id" => 7}, {"id" => 8}, {"id" => 9}]},
            scope: scope
          )
          expect(observed_scopes.size).to eq(3)
          expect(observed_scopes).to all(equal(scope))
        end
      end
    end
  end

  describe "(6) scope threads through self-recursive nesting (Comment → replies)" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "preserves scope identity at every level of the replies chain" do
          observed_scopes = []
          body = ->(_record, _context, scope) {
            observed_scopes << scope
            "ok"
          }
          comment = Panko::CodeGen::Descriptor.new(
            name: "ScopeRecursiveCommentSerializer_#{mode}",
            model: nil,
            parent_class: Fixtures::BaseSerializer,
            attributes: [attribute(:id)],
            method_attributes: [method_attribute(:tag, body)],
            associations: []
          )
          comment.associations << Panko::CodeGen::Association.new(
            name: :replies, kind: :has_many, descriptor: comment
          )
          generated = compile(comment, mode)
          scope = Object.new
          record = {
            "id" => 1,
            "replies" => [
              {"id" => 2, "replies" => [
                {"id" => 4, "replies" => []}
              ]},
              {"id" => 3, "replies" => []}
            ]
          }
          generated.serialize_one(record, scope: scope)
          # 4 Comment Records total: root + reply-2 + reply-2.4 + reply-3.
          expect(observed_scopes.size).to eq(4)
          expect(observed_scopes).to all(equal(scope))
        end
      end
    end
  end

  describe "(7) scope and context flow independently" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "scope-without-context works — context observed as nil, scope as supplied" do
          captured_context = :unset
          captured_scope = :unset
          body = ->(_record, context, scope) {
            captured_context = context
            captured_scope = scope
            "ok"
          }
          descriptor = descriptor_with(method_attributes: [method_attribute(:tag, body)])
          generated = compile(descriptor, mode)
          scope = Object.new
          generated.serialize_one({"id" => 1}, scope: scope)
          expect(captured_context).to be_nil
          expect(captured_scope).to equal(scope)
        end

        it "context-without-scope works — scope observed as nil, context as supplied" do
          captured_context = :unset
          captured_scope = :unset
          body = ->(_record, context, scope) {
            captured_context = context
            captured_scope = scope
            "ok"
          }
          descriptor = descriptor_with(method_attributes: [method_attribute(:tag, body)])
          generated = compile(descriptor, mode)
          context = Object.new
          generated.serialize_one({"id" => 1}, context: context)
          expect(captured_context).to equal(context)
          expect(captured_scope).to be_nil
        end
      end
    end
  end

  describe "(8) scope reaches Association if: arity-3 Callables" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "passes (record, context, scope) to a has_one if: guard" do
          captured_record = nil
          captured_context = nil
          captured_scope = nil
          guard = ->(record, context, scope) {
            captured_record = record
            captured_context = context
            captured_scope = scope
            true
          }
          inner = descriptor_with(
            name: "ScopeIfInnerSerializer_#{mode}",
            attributes: [attribute(:id)]
          )
          outer = descriptor_with(
            name: "ScopeIfOuterSerializer_#{mode}",
            attributes: [attribute(:id)],
            associations: [has_one(:child, descriptor: inner, if: guard)]
          )
          generated = compile(outer, mode)
          record = {"id" => 1, "child" => {"id" => 7}}
          context = Object.new
          scope = Object.new
          generated.serialize_one(record, context: context, scope: scope)
          expect(captured_record).to equal(record)
          expect(captured_context).to equal(context)
          expect(captured_scope).to equal(scope)
        end

        it "omits the Association when the arity-3 if: returns false based on scope" do
          guard = ->(_record, _context, scope) { !scope.nil? }
          inner = descriptor_with(
            name: "ScopeIfFalsyInnerSerializer_#{mode}",
            attributes: [attribute(:id)]
          )
          outer = descriptor_with(
            name: "ScopeIfFalsyOuterSerializer_#{mode}",
            attributes: [attribute(:id)],
            associations: [has_one(:child, descriptor: inner, if: guard)]
          )
          generated = compile(outer, mode)
          record = {"id" => 1, "child" => {"id" => 7}}
          # scope: nil → guard returns false → child omitted.
          omitted = generated.serialize_one(record)
          if mode == :json
            expect(omitted).to eq('{"id":1}')
          else
            expect(omitted).to eq({"id" => 1})
          end
          # scope: non-nil → guard returns true → child emitted.
          included = generated.serialize_one(record, scope: Object.new)
          if mode == :json
            expect(included).to eq('{"id":1,"child":{"id":7}}')
          else
            expect(included).to eq({"id" => 1, "child" => {"id" => 7}})
          end
        end
      end
    end
  end

  describe "(9) JSON and Hash modes produce equivalent observable behavior — scope is mode-agnostic" do
    it "scope-driven output is identical (modulo serialization) between :json and :hash" do
      body = ->(_record, _context, scope) { "viewer=#{scope}" }
      guard = ->(_record, _context, scope) { !scope.nil? }
      inner = descriptor_with(
        name: "ScopeModeAgnosticInnerSerializer",
        attributes: [attribute(:id), attribute(:name)]
      )
      outer = descriptor_with(
        name: "ScopeModeAgnosticOuterSerializer",
        attributes: [attribute(:id)],
        method_attributes: [method_attribute(:tag, body)],
        associations: [has_one(:child, descriptor: inner, if: guard)]
      )
      record = {"id" => 1, "child" => {"id" => 7, "name" => "alice"}}
      scope = "v1"

      json_generated = compile(outer, :json)
      hash_generated = compile(outer, :hash)

      json_output = json_generated.serialize_one(record, scope: scope)
      hash_output = hash_generated.serialize_one(record, scope: scope)

      expected_hash = {
        "id" => 1,
        "child" => {"id" => 7, "name" => "alice"},
        "tag" => "viewer=v1"
      }
      expect(hash_output).to eq(expected_hash)
      expect(Oj.load(json_output)).to eq(expected_hash)
    end
  end
end
