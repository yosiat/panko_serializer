# frozen_string_literal: true

require "panko/code_gen"
require "tmpdir"

RSpec.describe "Compile-time errors" do
  describe "Error hierarchy" do
    it "Error subclasses StandardError" do
      expect(Panko::CodeGen::Error.superclass).to eq(StandardError)
    end

    it "DescriptorError and CompileError are direct children of Error" do
      expect(Panko::CodeGen::DescriptorError.superclass).to eq(Panko::CodeGen::Error)
      expect(Panko::CodeGen::CompileError.superclass).to eq(Panko::CodeGen::Error)
    end

    it "NameCollisionError, UnknownSourceError, ArityError subclass CompileError" do
      expect(Panko::CodeGen::NameCollisionError.superclass).to eq(Panko::CodeGen::CompileError)
      expect(Panko::CodeGen::UnknownSourceError.superclass).to eq(Panko::CodeGen::CompileError)
      expect(Panko::CodeGen::ArityError.superclass).to eq(Panko::CodeGen::CompileError)
    end
  end

  describe "DescriptorError — structural, at Data.new" do
    describe "Descriptor (S1.4)" do
      let(:inner) {
        Panko::CodeGen::Descriptor.new(
          name: "InnerSerializer",
          model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [],
          method_attributes: [],
          associations: []
        )
      }

      it "constructs a frozen instance with all fields populated" do
        attr = Panko::CodeGen::Attribute.new(name: :id)
        ma = Panko::CodeGen::MethodAttribute.new(name: :computed, body: -> { 1 })
        assoc = Panko::CodeGen::Association.new(
          name: :inner, kind: :has_one, descriptor: inner
        )
        desc = Panko::CodeGen::Descriptor.new(
          name: "PostSerializer",
          model: String,
          parent_class: Fixtures::BaseSerializer,
          attributes: [attr],
          method_attributes: [ma],
          associations: [assoc]
        )
        expect(desc).to be_frozen
        expect(desc.name).to eq("PostSerializer")
        expect(desc.model).to eq(String)
        expect(desc.attributes).to eq([attr])
        expect(desc.method_attributes).to eq([ma])
        expect(desc.associations).to eq([assoc])
      end

      it "constructs with model: nil and empty Field arrays" do
        desc = Panko::CodeGen::Descriptor.new(
          name: "PostSerializer",
          model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [],
          method_attributes: [],
          associations: []
        )
        expect(desc).to be_frozen
        expect(desc.model).to be_nil
      end

      it "permits an Association whose descriptor is the parent (self-referential shape)" do
        parent = Panko::CodeGen::Descriptor.new(
          name: "CommentSerializer",
          model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [],
          method_attributes: [],
          associations: []
        )
        assoc = Panko::CodeGen::Association.new(
          name: :replies, kind: :has_many, descriptor: parent
        )
        expect(assoc.descriptor).to equal(parent)
      end

      it "raises when name is nil" do
        expect {
          Panko::CodeGen::Descriptor.new(
            name: nil, model: nil, attributes: [], method_attributes: [], associations: [], parent_class: Fixtures::BaseSerializer
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Descriptor#name/)
      end

      it "raises when name is an empty String" do
        expect {
          Panko::CodeGen::Descriptor.new(
            name: "", model: nil, attributes: [], method_attributes: [], associations: [], parent_class: Fixtures::BaseSerializer
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Descriptor#name/)
      end

      it "raises when model is neither nil nor a Class" do
        expect {
          Panko::CodeGen::Descriptor.new(
            name: "X", model: "NotAClass", attributes: [], method_attributes: [], associations: [], parent_class: Fixtures::BaseSerializer
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Descriptor#model/)
      end

      it "raises when attributes contains a non-Attribute element" do
        ma = Panko::CodeGen::MethodAttribute.new(name: :x, body: -> {})
        expect {
          Panko::CodeGen::Descriptor.new(
            name: "X", model: nil, attributes: [ma], method_attributes: [], associations: [], parent_class: Fixtures::BaseSerializer
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Descriptor#attributes/)
      end

      it "raises when method_attributes contains a non-MethodAttribute element" do
        attr = Panko::CodeGen::Attribute.new(name: :x)
        expect {
          Panko::CodeGen::Descriptor.new(
            name: "X", model: nil, attributes: [], method_attributes: [attr], associations: [], parent_class: Fixtures::BaseSerializer
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Descriptor#method_attributes/)
      end

      it "raises when associations contains a non-Association element" do
        attr = Panko::CodeGen::Attribute.new(name: :x)
        expect {
          Panko::CodeGen::Descriptor.new(
            name: "X", model: nil, attributes: [], method_attributes: [], associations: [attr], parent_class: Fixtures::BaseSerializer
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Descriptor#associations/)
      end

      it "raises when attributes is not an Array" do
        expect {
          Panko::CodeGen::Descriptor.new(
            name: "X", model: nil, attributes: nil, method_attributes: [], associations: [], parent_class: Fixtures::BaseSerializer
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Descriptor#attributes/)
      end

      it "raises when attributes contains a nil element" do
        expect {
          Panko::CodeGen::Descriptor.new(
            name: "X", model: nil, attributes: [nil], method_attributes: [], associations: [], parent_class: Fixtures::BaseSerializer
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Descriptor#attributes/)
      end

      it "raises when method_attributes contains a nil element" do
        expect {
          Panko::CodeGen::Descriptor.new(
            name: "X", model: nil, attributes: [], method_attributes: [nil], associations: [], parent_class: Fixtures::BaseSerializer
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Descriptor#method_attributes/)
      end

      it "raises when associations contains a nil element" do
        expect {
          Panko::CodeGen::Descriptor.new(
            name: "X", model: nil, attributes: [], method_attributes: [], associations: [nil], parent_class: Fixtures::BaseSerializer
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Descriptor#associations/)
      end

      it "parent_class: is required — raises ArgumentError when the kwarg is omitted" do
        expect {
          Panko::CodeGen::Descriptor.new(
            name: "X", model: nil, attributes: [], method_attributes: [], associations: []
          )
        }.to raise_error(ArgumentError, /parent_class/)
      end

      it "parent_class: accepts a Class" do
        desc = Panko::CodeGen::Descriptor.new(
          name: "X", model: nil, attributes: [], method_attributes: [], associations: [], parent_class: String
        )
        expect(desc.parent_class).to equal(String)
      end

      it "parent_class: raises when it is nil" do
        expect {
          Panko::CodeGen::Descriptor.new(
            name: "X", model: nil, attributes: [], method_attributes: [], associations: [], parent_class: nil
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Descriptor#parent_class/)
      end

      it "parent_class: raises when it is not a Class" do
        expect {
          Panko::CodeGen::Descriptor.new(
            name: "X", model: nil, attributes: [], method_attributes: [], associations: [], parent_class: "Object"
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Descriptor#parent_class/)
      end

      it "parent_class: raises when it is a Module that is not a Class" do
        mod = Module.new
        expect {
          Panko::CodeGen::Descriptor.new(
            name: "X", model: nil, attributes: [], method_attributes: [], associations: [], parent_class: mod
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Descriptor#parent_class/)
      end
    end

    describe "Attribute (S1.3)" do
      it "constructs a frozen instance with both fields populated" do
        attr = Panko::CodeGen::Attribute.new(name: :title, source: :raw_title)
        expect(attr).to be_frozen
        expect(attr.name).to eq(:title)
        expect(attr.source).to eq(:raw_title)
      end

      it "defaults source to name when omitted" do
        attr = Panko::CodeGen::Attribute.new(name: :title)
        expect(attr).to be_frozen
        expect(attr.source).to eq(:title)
      end

      it "raises when name is not a Symbol" do
        expect {
          Panko::CodeGen::Attribute.new(name: "title")
        }.to raise_error(Panko::CodeGen::DescriptorError)
      end

      it "raises when source is not a Symbol" do
        expect {
          Panko::CodeGen::Attribute.new(name: :title, source: "raw")
        }.to raise_error(Panko::CodeGen::DescriptorError)
      end
    end

    describe "MethodAttribute (S1.3)" do
      it "constructs a frozen instance with a Callable body" do
        ma = Panko::CodeGen::MethodAttribute.new(name: :likes_count, body: ->(r) { r.likes.count })
        expect(ma).to be_frozen
        expect(ma.name).to eq(:likes_count)
        expect(ma.body).to respond_to(:call)
      end

      it "raises when name is not a Symbol" do
        expect {
          Panko::CodeGen::MethodAttribute.new(name: "x", body: -> {})
        }.to raise_error(Panko::CodeGen::DescriptorError)
      end

      it "raises when body does not respond to #call" do
        expect {
          Panko::CodeGen::MethodAttribute.new(name: :x, body: 42)
        }.to raise_error(Panko::CodeGen::DescriptorError)
      end

      it "raises when body is an UnboundMethod (must be bound before inclusion)" do
        unbound = String.instance_method(:length)
        expect {
          Panko::CodeGen::MethodAttribute.new(name: :x, body: unbound)
        }.to raise_error(Panko::CodeGen::DescriptorError)
      end

      it "accepts a Symbol body without raising at structural validation (S18.1)" do
        ma = Panko::CodeGen::MethodAttribute.new(name: :greeting, body: :greeting)
        expect(ma).to be_frozen
        expect(ma.body).to eq(:greeting)
      end
    end

    describe "Association (S1.4)" do
      let(:inner) {
        Panko::CodeGen::Descriptor.new(
          name: "InnerSerializer",
          model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [],
          method_attributes: [],
          associations: []
        )
      }

      it "constructs a frozen instance with explicit fields" do
        assoc = Panko::CodeGen::Association.new(
          name: :author, kind: :has_one, descriptor: inner, source: :writer, if: nil
        )
        expect(assoc).to be_frozen
        expect(assoc.name).to eq(:author)
        expect(assoc.kind).to eq(:has_one)
        expect(assoc.descriptor).to equal(inner)
        expect(assoc.source).to eq(:writer)
        expect(assoc.if).to be_nil
      end

      it "defaults source to name when source kwarg is omitted" do
        assoc = Panko::CodeGen::Association.new(
          name: :author, kind: :has_one, descriptor: inner
        )
        expect(assoc.source).to eq(:author)
      end

      it "defaults source to name when source: nil is passed explicitly" do
        assoc = Panko::CodeGen::Association.new(
          name: :author, kind: :has_one, descriptor: inner, source: nil
        )
        expect(assoc.source).to eq(:author)
      end

      it "accepts kind: :has_many" do
        assoc = Panko::CodeGen::Association.new(
          name: :comments, kind: :has_many, descriptor: inner
        )
        expect(assoc.kind).to eq(:has_many)
      end

      it "accepts if: as a Lambda" do
        guard = ->(r, c) { true }
        assoc = Panko::CodeGen::Association.new(
          name: :author, kind: :has_one, descriptor: inner, if: guard
        )
        expect(assoc.if).to equal(guard)
      end

      it "raises when name is not a Symbol" do
        expect {
          Panko::CodeGen::Association.new(
            name: "author", kind: :has_one, descriptor: inner
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Association#name/)
      end

      it "raises when source is not a Symbol" do
        expect {
          Panko::CodeGen::Association.new(
            name: :author, kind: :has_one, descriptor: inner, source: "writer"
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Association#source/)
      end

      it "raises when kind is not :has_one or :has_many" do
        expect {
          Panko::CodeGen::Association.new(
            name: :author, kind: :has_any, descriptor: inner
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Association#kind/)
      end

      it "raises when kind is not a Symbol at all" do
        expect {
          Panko::CodeGen::Association.new(
            name: :author, kind: "has_one", descriptor: inner
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Association#kind/)
      end

      it "raises when descriptor is not a Descriptor" do
        expect {
          Panko::CodeGen::Association.new(
            name: :author, kind: :has_one, descriptor: "not a descriptor"
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Association#descriptor/)
      end

      it "raises when if: is present but not a Callable" do
        expect {
          Panko::CodeGen::Association.new(
            name: :author, kind: :has_one, descriptor: inner, if: 42
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Association#if/)
      end

      it "raises when if: is an UnboundMethod (must be bound before inclusion)" do
        unbound = String.instance_method(:length)
        expect {
          Panko::CodeGen::Association.new(
            name: :author, kind: :has_one, descriptor: inner, if: unbound
          )
        }.to raise_error(Panko::CodeGen::DescriptorError, /Association#if/)
      end

      it "rejects unknown keyword arguments (e.g. typo'd source) instead of silently dropping them" do
        expect {
          Panko::CodeGen::Association.new(
            name: :author, kind: :has_one, descriptor: inner, sourrce: :writer
          )
        }.to raise_error(ArgumentError, /sourrce/)
      end
    end
  end

  describe "CompileError subclasses" do
    describe "NameCollisionError (S9)" do
      let(:inner) {
        Panko::CodeGen::Descriptor.new(
          name: "InnerDescriptor", model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [], method_attributes: [], associations: []
        )
      }

      it "raises when two Attributes share a name" do
        descriptor = Panko::CodeGen::Descriptor.new(
          name: "PostDescriptor", model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [
            Panko::CodeGen::Attribute.new(name: :id),
            Panko::CodeGen::Attribute.new(name: :id)
          ],
          method_attributes: [], associations: []
        )
        expect {
          Panko::CodeGen.compile(descriptor, output: :json)
        }.to raise_error(
          Panko::CodeGen::NameCollisionError,
          "PostDescriptor#id: Attribute and Attribute share name; every Field at the same level must have a unique name."
        )
      end

      it "raises when an Attribute and a MethodAttribute share a name" do
        descriptor = Panko::CodeGen::Descriptor.new(
          name: "PostDescriptor", model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [Panko::CodeGen::Attribute.new(name: :id)],
          method_attributes: [Panko::CodeGen::MethodAttribute.new(name: :id, body: -> { "computed" })],
          associations: []
        )
        expect {
          Panko::CodeGen.compile(descriptor, output: :json)
        }.to raise_error(
          Panko::CodeGen::NameCollisionError,
          "PostDescriptor#id: Attribute and MethodAttribute share name; every Field at the same level must have a unique name."
        )
      end

      it "raises when an Attribute and an Association share a name" do
        descriptor = Panko::CodeGen::Descriptor.new(
          name: "PostDescriptor", model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [Panko::CodeGen::Attribute.new(name: :author)],
          method_attributes: [],
          associations: [Panko::CodeGen::Association.new(name: :author, kind: :has_one, descriptor: inner)]
        )
        expect {
          Panko::CodeGen.compile(descriptor, output: :json)
        }.to raise_error(
          Panko::CodeGen::NameCollisionError,
          "PostDescriptor#author: Attribute and Association share name; every Field at the same level must have a unique name."
        )
      end

      it "raises when a MethodAttribute and an Association share a name" do
        descriptor = Panko::CodeGen::Descriptor.new(
          name: "PostDescriptor", model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [],
          method_attributes: [Panko::CodeGen::MethodAttribute.new(name: :author, body: -> { :ok })],
          associations: [Panko::CodeGen::Association.new(name: :author, kind: :has_one, descriptor: inner)]
        )
        expect {
          Panko::CodeGen.compile(descriptor, output: :json)
        }.to raise_error(
          Panko::CodeGen::NameCollisionError,
          "PostDescriptor#author: MethodAttribute and Association share name; every Field at the same level must have a unique name."
        )
      end

      it "names the nested Descriptor when collision is inside a nested Descriptor" do
        nested = Panko::CodeGen::Descriptor.new(
          name: "AuthorDescriptor", model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [Panko::CodeGen::Attribute.new(name: :name)],
          method_attributes: [],
          associations: [Panko::CodeGen::Association.new(name: :name, kind: :has_one, descriptor: inner)]
        )
        outer = Panko::CodeGen::Descriptor.new(
          name: "PostDescriptor", model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [], method_attributes: [],
          associations: [Panko::CodeGen::Association.new(name: :author, kind: :has_one, descriptor: nested)]
        )
        expect {
          Panko::CodeGen.compile(outer, output: :json)
        }.to raise_error(
          Panko::CodeGen::NameCollisionError,
          "AuthorDescriptor#name: Attribute and Association share name; every Field at the same level must have a unique name."
        )
      end

      it "does not raise when the same name appears at different levels" do
        nested = Panko::CodeGen::Descriptor.new(
          name: "AuthorDescriptor", model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [Panko::CodeGen::Attribute.new(name: :id)],
          method_attributes: [], associations: []
        )
        outer = Panko::CodeGen::Descriptor.new(
          name: "PostDescriptor", model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [Panko::CodeGen::Attribute.new(name: :id)],
          method_attributes: [],
          associations: [Panko::CodeGen::Association.new(name: :author, kind: :has_one, descriptor: nested)]
        )
        expect {
          Panko::CodeGen.compile(outer, output: :json)
        }.not_to raise_error
      end
    end

    describe "UnknownSourceError (S6)" do
      def fake_ar_class(name:, columns: [], methods: [])
        columns_arr = columns
        methods_arr = methods
        Class.new do
          define_singleton_method(:name) { name }
          define_singleton_method(:columns_hash) { columns_arr.to_h { |c| [c, :stub] } }
          define_singleton_method(:method_defined?) { |sym| methods_arr.include?(sym.to_sym) }
          define_singleton_method(:attribute_methods_generated?) { true }
          define_singleton_method(:define_attribute_methods) { nil }
          # The Specialized JSON-mode emit calls AccessClassifier.json_typed? on
          # every Models entry to decide whether the JSON-column raw-passthrough
          # path applies. Faking +type_for_attribute+ to return a non-Json type
          # value mirrors AR's "unknown column" fallback so the per-Attribute
          # decision stays a clean +false+ in these tests.
          define_singleton_method(:type_for_attribute) { |_name| ::ActiveModel::Type::Value.new }
        end
      end

      def descriptor_with_attribute(name:, source:, model:)
        Panko::CodeGen::Descriptor.new(
          name: "PostDescriptor",
          model: model,
          parent_class: Fixtures::BaseSerializer,
          attributes: [Panko::CodeGen::Attribute.new(name: name, source: source)],
          method_attributes: [],
          associations: []
        )
      end

      it "does not raise when source is a column-backed Attribute on the single Model" do
        klass = fake_ar_class(name: "Post", columns: ["title"])
        descriptor = descriptor_with_attribute(name: :title, source: :title, model: klass)
        expect {
          Panko::CodeGen.compile(descriptor, output: :json)
        }.not_to raise_error
      end

      it "does not raise when source is an instance method on the single Model" do
        klass = fake_ar_class(name: "Post", columns: ["id"], methods: %i[full_title])
        descriptor = descriptor_with_attribute(name: :full_title, source: :full_title, model: klass)
        expect {
          Panko::CodeGen.compile(descriptor, output: :json)
        }.not_to raise_error
      end

      it "raises when source is neither a column nor an instance method on the single Model" do
        klass = fake_ar_class(name: "Post", columns: ["id"], methods: %i[full_title])
        descriptor = descriptor_with_attribute(name: :missing, source: :missing, model: klass)
        expect {
          Panko::CodeGen.compile(descriptor, output: :json)
        }.to raise_error(Panko::CodeGen::UnknownSourceError, /not a column or instance method on Post/)
      end

      it "does not raise at Compile when Model is nil (defers to runtime NoMethodError)" do
        descriptor = descriptor_with_attribute(name: :title, source: :title, model: nil)
        expect {
          Panko::CodeGen.compile(descriptor, output: :json)
        }.not_to raise_error
      end

      it "does not raise when model is a non-AR class (falls through to method dispatch)" do
        non_ar = Class.new { def self.name = "PlainClass" }
        descriptor = descriptor_with_attribute(name: :anything, source: :anything, model: non_ar)
        expect {
          Panko::CodeGen.compile(descriptor, output: :json)
        }.not_to raise_error
      end
    end

    describe "ArityError (S4)" do
      def descriptor_with_method_attribute(name:, body:)
        Panko::CodeGen::Descriptor.new(
          name: "PostDescriptor",
          model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [],
          method_attributes: [Panko::CodeGen::MethodAttribute.new(name: name, body: body)],
          associations: []
        )
      end

      def descriptor_with_association_if(name:, if_callable:)
        inner = Panko::CodeGen::Descriptor.new(
          name: "InnerDescriptor", model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [], method_attributes: [], associations: []
        )
        Panko::CodeGen::Descriptor.new(
          name: "PostDescriptor",
          model: nil,
          parent_class: Fixtures::BaseSerializer,
          attributes: [],
          method_attributes: [],
          associations: [
            Panko::CodeGen::Association.new(
              name: name, kind: :has_one, descriptor: inner, if: if_callable
            )
          ]
        )
      end

      {
        4 => ->(_a, _b, _c, _d) { :ok },
        -1 => ->(*_args) { :ok },
        -2 => ->(_a, *_rest) { :ok },
        -3 => ->(_a, _b, *_rest) { :ok }
      }.each do |arity, body|
        it "raises when MethodAttribute body has arity #{arity}" do
          descriptor = descriptor_with_method_attribute(name: :likes_count, body: body)
          expect {
            Panko::CodeGen.compile(descriptor, output: :json)
          }.to raise_error(Panko::CodeGen::ArityError, /arity #{arity}/)
        end
      end

      {
        4 => ->(_a, _b, _c, _d) { true },
        -1 => ->(*_args) { true },
        -2 => ->(_a, *_rest) { true },
        -3 => ->(_a, _b, *_rest) { true }
      }.each do |arity, body|
        it "raises when Association if: has arity #{arity}" do
          descriptor = descriptor_with_association_if(name: :author, if_callable: body)
          expect {
            Panko::CodeGen.compile(descriptor, output: :json)
          }.to raise_error(
            Panko::CodeGen::ArityError,
            "PostDescriptor#author: Association#if has arity #{arity}; must be 0, 1, 2, or 3."
          )
        end
      end

      {
        0 => -> { :ok },
        1 => ->(_record) { :ok },
        2 => ->(_record, _context) { :ok },
        3 => ->(_record, _context, _scope) { :ok }
      }.each do |arity, body|
        it "compiles when MethodAttribute body has arity #{arity}" do
          descriptor = descriptor_with_method_attribute(name: :computed, body: body)
          expect {
            Panko::CodeGen.compile(descriptor, output: :json)
          }.not_to raise_error
        end
      end

      {
        0 => -> { true },
        1 => ->(_record) { true },
        2 => ->(_record, _context) { true },
        3 => ->(_record, _context, _scope) { true }
      }.each do |arity, body|
        it "compiles when Association if: has arity #{arity}" do
          descriptor = descriptor_with_association_if(name: :author, if_callable: body)
          expect {
            Panko::CodeGen.compile(descriptor, output: :json)
          }.not_to raise_error
        end
      end
    end
  end

  describe "Message convention" do
    it "DescriptorError names the Field, kind, rule, and observed value (S1.3 / S1.4)" do
      expect {
        Panko::CodeGen::Attribute.new(name: "title")
      }.to raise_error(Panko::CodeGen::DescriptorError) { |err|
        expect(err.message).to include("Attribute#name")
        expect(err.message).to include("Symbol")
        expect(err.message).to include('"title"')
      }
    end

    it "NameCollisionError names the Descriptor, Field name, and rule (S9)" do
      descriptor = Panko::CodeGen::Descriptor.new(
        name: "PostDescriptor", model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [Panko::CodeGen::Attribute.new(name: :id)],
        method_attributes: [Panko::CodeGen::MethodAttribute.new(name: :id, body: -> { "computed" })],
        associations: []
      )
      expect {
        Panko::CodeGen.compile(descriptor, output: :json)
      }.to raise_error(
        Panko::CodeGen::NameCollisionError,
        "PostDescriptor#id: Attribute and MethodAttribute share name; every Field at the same level must have a unique name."
      )
    end

    it "UnknownSourceError names the Descriptor, Field name, rule, and observed Source (S6)" do
      klass = Class.new do
        def self.name = "Post"

        def self.columns_hash = {"id" => :stub}

        def self.method_defined?(_sym) = false

        def self.attribute_methods_generated? = true

        def self.define_attribute_methods = nil
      end
      descriptor = Panko::CodeGen::Descriptor.new(
        name: "PostDescriptor",
        model: klass,
        parent_class: Fixtures::BaseSerializer,
        attributes: [Panko::CodeGen::Attribute.new(name: :title, source: :raw_title)],
        method_attributes: [],
        associations: []
      )
      expect {
        Panko::CodeGen.compile(descriptor, output: :json)
      }.to raise_error(
        Panko::CodeGen::UnknownSourceError,
        "PostDescriptor#title: Attribute#source :raw_title is not a column or instance method on Post."
      )
    end

    it "ArityError matches the docs/errors.md § Message convention example (S4)" do
      descriptor = Panko::CodeGen::Descriptor.new(
        name: "PostDescriptor",
        model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [],
        method_attributes: [
          Panko::CodeGen::MethodAttribute.new(name: :likes_count, body: ->(_a, _b, _c, _d) { :ok })
        ],
        associations: []
      )
      expect {
        Panko::CodeGen.compile(descriptor, output: :json)
      }.to raise_error(
        Panko::CodeGen::ArityError,
        "PostDescriptor#likes_count: MethodAttribute#body has arity 4; must be 0, 1, 2, or 3."
      )
    end
  end

  describe "SKIP singleton (S1.3)" do
    it "is identity-stable via #equal?" do
      expect(Panko::CodeGen::SKIP.equal?(Panko::CodeGen::SKIP)).to be(true)
    end

    it "is frozen" do
      expect(Panko::CodeGen::SKIP).to be_frozen
    end
  end

  describe "Dump-side parity — Dump shares Validator with Compiler (S15.6)" do
    # +Dump+ runs the same +Validators::Validator+ rule list as +Compiler+
    # before reaching +File.write+, so the same +Descriptor+ that breaks
    # under +Panko::CodeGen.compile+ must raise the same +CompileError+
    # subclass under +Panko::CodeGen.dump+. Path validation runs
    # first, so we hand a syntactically-valid (non-empty String) +path:+
    # under a fresh +Dir.mktmpdir+; the validator raises before any
    # +File.write+ side effect, so the tmp dir stays empty.

    it "ArityError parity — Dump raises the same class as Compile (S4)" do
      descriptor = Panko::CodeGen::Descriptor.new(
        name: "PostDescriptor",
        model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [],
        method_attributes: [
          Panko::CodeGen::MethodAttribute.new(name: :likes_count, body: ->(_a, _b, _c, _d) { :ok })
        ],
        associations: []
      )
      Dir.mktmpdir do |dir|
        target = File.join(dir, "post_descriptor_json.rb")
        expect {
          Panko::CodeGen.dump(descriptor, output: :json, path: target)
        }.to raise_error(
          Panko::CodeGen::ArityError,
          "PostDescriptor#likes_count: MethodAttribute#body has arity 4; must be 0, 1, 2, or 3."
        )
        expect(Dir.children(dir)).to be_empty
      end
    end

    it "NameCollisionError parity — Dump raises the same class as Compile (S9)" do
      descriptor = Panko::CodeGen::Descriptor.new(
        name: "PostDescriptor",
        model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [
          Panko::CodeGen::Attribute.new(name: :id),
          Panko::CodeGen::Attribute.new(name: :id)
        ],
        method_attributes: [],
        associations: []
      )
      Dir.mktmpdir do |dir|
        target = File.join(dir, "post_descriptor_json.rb")
        expect {
          Panko::CodeGen.dump(descriptor, output: :json, path: target)
        }.to raise_error(
          Panko::CodeGen::NameCollisionError,
          "PostDescriptor#id: Attribute and Attribute share name; every Field at the same level must have a unique name."
        )
        expect(Dir.children(dir)).to be_empty
      end
    end

    it "UnknownSourceError parity — Dump raises the same class as Compile (S6)" do
      klass = Class.new do
        def self.name = "Post"

        def self.columns_hash = {"id" => :stub}

        def self.method_defined?(_sym) = false

        def self.attribute_methods_generated? = true

        def self.define_attribute_methods = nil

        def self.type_for_attribute(_name) = ::ActiveModel::Type::Value.new
      end
      descriptor = Panko::CodeGen::Descriptor.new(
        name: "PostDescriptor",
        model: klass,
        parent_class: Fixtures::BaseSerializer,
        attributes: [Panko::CodeGen::Attribute.new(name: :missing, source: :missing)],
        method_attributes: [],
        associations: []
      )
      Dir.mktmpdir do |dir|
        target = File.join(dir, "post_descriptor_json.rb")
        expect {
          Panko::CodeGen.dump(descriptor, output: :json, path: target)
        }.to raise_error(
          Panko::CodeGen::UnknownSourceError,
          "PostDescriptor#missing: Attribute#source :missing is not a column or instance method on Post."
        )
        expect(Dir.children(dir)).to be_empty
      end
    end
  end

  describe "Mode independence — semantic validation runs pre-Generator" do
    def unknown_source_descriptor
      klass = Class.new do
        def self.name = "Post"

        def self.columns_hash = {"id" => :stub}

        def self.method_defined?(_sym) = false

        def self.attribute_methods_generated? = true

        def self.define_attribute_methods = nil
      end
      Panko::CodeGen::Descriptor.new(
        name: "PostDescriptor",
        model: klass,
        parent_class: Fixtures::BaseSerializer,
        attributes: [Panko::CodeGen::Attribute.new(name: :missing, source: :missing)],
        method_attributes: [],
        associations: []
      )
    end

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "NameCollisionError raises before Generator emit (S9)" do
          descriptor = Panko::CodeGen::Descriptor.new(
            name: "PostDescriptor", model: nil,
            parent_class: Fixtures::BaseSerializer,
            attributes: [
              Panko::CodeGen::Attribute.new(name: :id),
              Panko::CodeGen::Attribute.new(name: :id)
            ],
            method_attributes: [], associations: []
          )
          expect {
            Panko::CodeGen.compile(descriptor, output: mode)
          }.to raise_error(Panko::CodeGen::NameCollisionError, /Attribute and Attribute share name/)
        end

        it "UnknownSourceError raises before Generator emit (S6)" do
          expect {
            Panko::CodeGen.compile(unknown_source_descriptor, output: mode)
          }.to raise_error(Panko::CodeGen::UnknownSourceError, /not a column or instance method on Post/)
        end

        it "ArityError raises before Generator emit (S4)" do
          descriptor = Panko::CodeGen::Descriptor.new(
            name: "PostDescriptor",
            model: nil,
            parent_class: Fixtures::BaseSerializer,
            attributes: [],
            method_attributes: [
              Panko::CodeGen::MethodAttribute.new(name: :likes_count, body: ->(_a, _b, _c, _d) { :ok })
            ],
            associations: []
          )
          expect {
            Panko::CodeGen.compile(descriptor, output: mode)
          }.to raise_error(Panko::CodeGen::ArityError, /MethodAttribute#body has arity 4/)
        end
      end
    end
  end
end
