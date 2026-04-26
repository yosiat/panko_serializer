# frozen_string_literal: true

require "serializers_code_gen"

RSpec.describe "Compile-time errors" do
  describe "Error hierarchy" do
    it "Error subclasses StandardError" do
      expect(SerializersCodeGen::Error.superclass).to eq(StandardError)
    end

    it "DescriptorError and CompileError are direct children of Error" do
      expect(SerializersCodeGen::DescriptorError.superclass).to eq(SerializersCodeGen::Error)
      expect(SerializersCodeGen::CompileError.superclass).to eq(SerializersCodeGen::Error)
    end

    it "NameCollisionError, UnknownSourceError, ArityError subclass CompileError" do
      expect(SerializersCodeGen::NameCollisionError.superclass).to eq(SerializersCodeGen::CompileError)
      expect(SerializersCodeGen::UnknownSourceError.superclass).to eq(SerializersCodeGen::CompileError)
      expect(SerializersCodeGen::ArityError.superclass).to eq(SerializersCodeGen::CompileError)
    end
  end

  describe "DescriptorError — structural, at Data.new" do
    describe "Descriptor (S1.4)" do
      let(:inner) {
        SerializersCodeGen::Descriptor.new(
          name: "InnerSerializer",
          models: nil,
          attributes: [],
          method_attributes: [],
          associations: []
        )
      }

      it "constructs a frozen instance with all fields populated" do
        attr = SerializersCodeGen::Attribute.new(name: :id)
        ma = SerializersCodeGen::MethodAttribute.new(name: :computed, body: -> { 1 })
        assoc = SerializersCodeGen::Association.new(
          name: :inner, kind: :has_one, descriptor: inner
        )
        desc = SerializersCodeGen::Descriptor.new(
          name: "PostSerializer",
          models: [String, Integer],
          attributes: [attr],
          method_attributes: [ma],
          associations: [assoc]
        )
        expect(desc).to be_frozen
        expect(desc.name).to eq("PostSerializer")
        expect(desc.models).to eq([String, Integer])
        expect(desc.attributes).to eq([attr])
        expect(desc.method_attributes).to eq([ma])
        expect(desc.associations).to eq([assoc])
      end

      it "constructs with models: nil and empty Field arrays" do
        desc = SerializersCodeGen::Descriptor.new(
          name: "PostSerializer",
          models: nil,
          attributes: [],
          method_attributes: [],
          associations: []
        )
        expect(desc).to be_frozen
        expect(desc.models).to be_nil
      end

      it "permits an Association whose descriptor is the parent (self-referential shape)" do
        parent = SerializersCodeGen::Descriptor.new(
          name: "CommentSerializer",
          models: nil,
          attributes: [],
          method_attributes: [],
          associations: []
        )
        assoc = SerializersCodeGen::Association.new(
          name: :replies, kind: :has_many, descriptor: parent
        )
        expect(assoc.descriptor).to equal(parent)
      end

      it "raises when name is nil" do
        expect {
          SerializersCodeGen::Descriptor.new(
            name: nil, models: nil, attributes: [], method_attributes: [], associations: []
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Descriptor#name/)
      end

      it "raises when name is an empty String" do
        expect {
          SerializersCodeGen::Descriptor.new(
            name: "", models: nil, attributes: [], method_attributes: [], associations: []
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Descriptor#name/)
      end

      it "raises when models contains a non-Class element" do
        expect {
          SerializersCodeGen::Descriptor.new(
            name: "X", models: ["NotAClass"], attributes: [], method_attributes: [], associations: []
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Descriptor#models/)
      end

      it "raises when models is not nil and not an Array" do
        expect {
          SerializersCodeGen::Descriptor.new(
            name: "X", models: String, attributes: [], method_attributes: [], associations: []
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Descriptor#models/)
      end

      it "raises when attributes contains a non-Attribute element" do
        ma = SerializersCodeGen::MethodAttribute.new(name: :x, body: -> {})
        expect {
          SerializersCodeGen::Descriptor.new(
            name: "X", models: nil, attributes: [ma], method_attributes: [], associations: []
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Descriptor#attributes/)
      end

      it "raises when method_attributes contains a non-MethodAttribute element" do
        attr = SerializersCodeGen::Attribute.new(name: :x)
        expect {
          SerializersCodeGen::Descriptor.new(
            name: "X", models: nil, attributes: [], method_attributes: [attr], associations: []
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Descriptor#method_attributes/)
      end

      it "raises when associations contains a non-Association element" do
        attr = SerializersCodeGen::Attribute.new(name: :x)
        expect {
          SerializersCodeGen::Descriptor.new(
            name: "X", models: nil, attributes: [], method_attributes: [], associations: [attr]
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Descriptor#associations/)
      end

      it "raises when attributes is not an Array" do
        expect {
          SerializersCodeGen::Descriptor.new(
            name: "X", models: nil, attributes: nil, method_attributes: [], associations: []
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Descriptor#attributes/)
      end

      it "raises when attributes contains a nil element" do
        expect {
          SerializersCodeGen::Descriptor.new(
            name: "X", models: nil, attributes: [nil], method_attributes: [], associations: []
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Descriptor#attributes/)
      end

      it "raises when method_attributes contains a nil element" do
        expect {
          SerializersCodeGen::Descriptor.new(
            name: "X", models: nil, attributes: [], method_attributes: [nil], associations: []
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Descriptor#method_attributes/)
      end

      it "raises when associations contains a nil element" do
        expect {
          SerializersCodeGen::Descriptor.new(
            name: "X", models: nil, attributes: [], method_attributes: [], associations: [nil]
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Descriptor#associations/)
      end
    end

    describe "Attribute (S1.3)" do
      it "constructs a frozen instance with both fields populated" do
        attr = SerializersCodeGen::Attribute.new(name: :title, source: :raw_title)
        expect(attr).to be_frozen
        expect(attr.name).to eq(:title)
        expect(attr.source).to eq(:raw_title)
      end

      it "defaults source to name when omitted" do
        attr = SerializersCodeGen::Attribute.new(name: :title)
        expect(attr).to be_frozen
        expect(attr.source).to eq(:title)
      end

      it "raises when name is not a Symbol" do
        expect {
          SerializersCodeGen::Attribute.new(name: "title")
        }.to raise_error(SerializersCodeGen::DescriptorError)
      end

      it "raises when source is not a Symbol" do
        expect {
          SerializersCodeGen::Attribute.new(name: :title, source: "raw")
        }.to raise_error(SerializersCodeGen::DescriptorError)
      end
    end

    describe "MethodAttribute (S1.3)" do
      it "constructs a frozen instance with a Callable body" do
        ma = SerializersCodeGen::MethodAttribute.new(name: :likes_count, body: ->(r) { r.likes.count })
        expect(ma).to be_frozen
        expect(ma.name).to eq(:likes_count)
        expect(ma.body).to respond_to(:call)
      end

      it "raises when name is not a Symbol" do
        expect {
          SerializersCodeGen::MethodAttribute.new(name: "x", body: -> {})
        }.to raise_error(SerializersCodeGen::DescriptorError)
      end

      it "raises when body does not respond to #call" do
        expect {
          SerializersCodeGen::MethodAttribute.new(name: :x, body: 42)
        }.to raise_error(SerializersCodeGen::DescriptorError)
      end

      it "raises when body is an UnboundMethod (must be bound before inclusion)" do
        unbound = String.instance_method(:length)
        expect {
          SerializersCodeGen::MethodAttribute.new(name: :x, body: unbound)
        }.to raise_error(SerializersCodeGen::DescriptorError)
      end
    end

    describe "Association (S1.4)" do
      let(:inner) {
        SerializersCodeGen::Descriptor.new(
          name: "InnerSerializer",
          models: nil,
          attributes: [],
          method_attributes: [],
          associations: []
        )
      }

      it "constructs a frozen instance with explicit fields" do
        assoc = SerializersCodeGen::Association.new(
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
        assoc = SerializersCodeGen::Association.new(
          name: :author, kind: :has_one, descriptor: inner
        )
        expect(assoc.source).to eq(:author)
      end

      it "defaults source to name when source: nil is passed explicitly" do
        assoc = SerializersCodeGen::Association.new(
          name: :author, kind: :has_one, descriptor: inner, source: nil
        )
        expect(assoc.source).to eq(:author)
      end

      it "accepts kind: :has_many" do
        assoc = SerializersCodeGen::Association.new(
          name: :comments, kind: :has_many, descriptor: inner
        )
        expect(assoc.kind).to eq(:has_many)
      end

      it "accepts if: as a Lambda" do
        guard = ->(r, c) { true }
        assoc = SerializersCodeGen::Association.new(
          name: :author, kind: :has_one, descriptor: inner, if: guard
        )
        expect(assoc.if).to equal(guard)
      end

      it "raises when name is not a Symbol" do
        expect {
          SerializersCodeGen::Association.new(
            name: "author", kind: :has_one, descriptor: inner
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Association#name/)
      end

      it "raises when source is not a Symbol" do
        expect {
          SerializersCodeGen::Association.new(
            name: :author, kind: :has_one, descriptor: inner, source: "writer"
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Association#source/)
      end

      it "raises when kind is not :has_one or :has_many" do
        expect {
          SerializersCodeGen::Association.new(
            name: :author, kind: :has_any, descriptor: inner
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Association#kind/)
      end

      it "raises when kind is not a Symbol at all" do
        expect {
          SerializersCodeGen::Association.new(
            name: :author, kind: "has_one", descriptor: inner
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Association#kind/)
      end

      it "raises when descriptor is not a Descriptor" do
        expect {
          SerializersCodeGen::Association.new(
            name: :author, kind: :has_one, descriptor: "not a descriptor"
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Association#descriptor/)
      end

      it "raises when if: is present but not a Callable" do
        expect {
          SerializersCodeGen::Association.new(
            name: :author, kind: :has_one, descriptor: inner, if: 42
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Association#if/)
      end

      it "raises when if: is an UnboundMethod (must be bound before inclusion)" do
        unbound = String.instance_method(:length)
        expect {
          SerializersCodeGen::Association.new(
            name: :author, kind: :has_one, descriptor: inner, if: unbound
          )
        }.to raise_error(SerializersCodeGen::DescriptorError, /Association#if/)
      end

      it "rejects unknown keyword arguments (e.g. typo'd source) instead of silently dropping them" do
        expect {
          SerializersCodeGen::Association.new(
            name: :author, kind: :has_one, descriptor: inner, sourrce: :writer
          )
        }.to raise_error(ArgumentError, /sourrce/)
      end
    end
  end

  describe "CompileError subclasses" do
    describe "NameCollisionError (S9)" do
      let(:inner) {
        SerializersCodeGen::Descriptor.new(
          name: "InnerDescriptor", models: nil,
          attributes: [], method_attributes: [], associations: []
        )
      }

      it "raises when two Attributes share a name" do
        descriptor = SerializersCodeGen::Descriptor.new(
          name: "PostDescriptor", models: nil,
          attributes: [
            SerializersCodeGen::Attribute.new(name: :id),
            SerializersCodeGen::Attribute.new(name: :id)
          ],
          method_attributes: [], associations: []
        )
        expect {
          SerializersCodeGen.compile(descriptor, output: :json)
        }.to raise_error(
          SerializersCodeGen::NameCollisionError,
          "PostDescriptor#id: Attribute and Attribute share name; every Field at the same level must have a unique name."
        )
      end

      it "raises when an Attribute and a MethodAttribute share a name" do
        descriptor = SerializersCodeGen::Descriptor.new(
          name: "PostDescriptor", models: nil,
          attributes: [SerializersCodeGen::Attribute.new(name: :id)],
          method_attributes: [SerializersCodeGen::MethodAttribute.new(name: :id, body: -> { "computed" })],
          associations: []
        )
        expect {
          SerializersCodeGen.compile(descriptor, output: :json)
        }.to raise_error(
          SerializersCodeGen::NameCollisionError,
          "PostDescriptor#id: Attribute and MethodAttribute share name; every Field at the same level must have a unique name."
        )
      end

      it "raises when an Attribute and an Association share a name" do
        descriptor = SerializersCodeGen::Descriptor.new(
          name: "PostDescriptor", models: nil,
          attributes: [SerializersCodeGen::Attribute.new(name: :author)],
          method_attributes: [],
          associations: [SerializersCodeGen::Association.new(name: :author, kind: :has_one, descriptor: inner)]
        )
        expect {
          SerializersCodeGen.compile(descriptor, output: :json)
        }.to raise_error(
          SerializersCodeGen::NameCollisionError,
          "PostDescriptor#author: Attribute and Association share name; every Field at the same level must have a unique name."
        )
      end

      it "raises when a MethodAttribute and an Association share a name" do
        descriptor = SerializersCodeGen::Descriptor.new(
          name: "PostDescriptor", models: nil,
          attributes: [],
          method_attributes: [SerializersCodeGen::MethodAttribute.new(name: :author, body: -> { :ok })],
          associations: [SerializersCodeGen::Association.new(name: :author, kind: :has_one, descriptor: inner)]
        )
        expect {
          SerializersCodeGen.compile(descriptor, output: :json)
        }.to raise_error(
          SerializersCodeGen::NameCollisionError,
          "PostDescriptor#author: MethodAttribute and Association share name; every Field at the same level must have a unique name."
        )
      end

      it "names the nested Descriptor when collision is inside a nested Descriptor" do
        nested = SerializersCodeGen::Descriptor.new(
          name: "AuthorDescriptor", models: nil,
          attributes: [SerializersCodeGen::Attribute.new(name: :name)],
          method_attributes: [],
          associations: [SerializersCodeGen::Association.new(name: :name, kind: :has_one, descriptor: inner)]
        )
        outer = SerializersCodeGen::Descriptor.new(
          name: "PostDescriptor", models: nil,
          attributes: [], method_attributes: [],
          associations: [SerializersCodeGen::Association.new(name: :author, kind: :has_one, descriptor: nested)]
        )
        expect {
          SerializersCodeGen.compile(outer, output: :json)
        }.to raise_error(
          SerializersCodeGen::NameCollisionError,
          "AuthorDescriptor#name: Attribute and Association share name; every Field at the same level must have a unique name."
        )
      end

      it "does not raise when the same name appears at different levels" do
        nested = SerializersCodeGen::Descriptor.new(
          name: "AuthorDescriptor", models: nil,
          attributes: [SerializersCodeGen::Attribute.new(name: :id)],
          method_attributes: [], associations: []
        )
        outer = SerializersCodeGen::Descriptor.new(
          name: "PostDescriptor", models: nil,
          attributes: [SerializersCodeGen::Attribute.new(name: :id)],
          method_attributes: [],
          associations: [SerializersCodeGen::Association.new(name: :author, kind: :has_one, descriptor: nested)]
        )
        expect {
          SerializersCodeGen.compile(outer, output: :json)
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
        end
      end

      def descriptor_with_attribute(name:, source:, models:)
        SerializersCodeGen::Descriptor.new(
          name: "PostDescriptor",
          models: models,
          attributes: [SerializersCodeGen::Attribute.new(name: name, source: source)],
          method_attributes: [],
          associations: []
        )
      end

      it "does not raise when source is a column-backed Attribute on the single Model" do
        klass = fake_ar_class(name: "Post", columns: ["title"])
        descriptor = descriptor_with_attribute(name: :title, source: :title, models: [klass])
        expect {
          SerializersCodeGen.compile(descriptor, output: :json)
        }.not_to raise_error
      end

      it "does not raise when source is an instance method on the single Model" do
        klass = fake_ar_class(name: "Post", columns: ["id"], methods: %i[full_title])
        descriptor = descriptor_with_attribute(name: :full_title, source: :full_title, models: [klass])
        expect {
          SerializersCodeGen.compile(descriptor, output: :json)
        }.not_to raise_error
      end

      it "raises when source is neither a column nor an instance method on the single Model" do
        klass = fake_ar_class(name: "Post", columns: ["id"], methods: %i[full_title])
        descriptor = descriptor_with_attribute(name: :missing, source: :missing, models: [klass])
        expect {
          SerializersCodeGen.compile(descriptor, output: :json)
        }.to raise_error(SerializersCodeGen::UnknownSourceError, /not a column or instance method on Post/)
      end

      it "does not raise at Compile when Models is nil (defers to runtime NoMethodError)" do
        descriptor = descriptor_with_attribute(name: :title, source: :title, models: nil)
        expect {
          SerializersCodeGen.compile(descriptor, output: :json)
        }.not_to raise_error
      end

      it "does not raise when models contains a non-AR class (falls through to method dispatch)" do
        non_ar = Class.new { def self.name = "PlainClass" }
        descriptor = descriptor_with_attribute(name: :anything, source: :anything, models: [non_ar])
        expect {
          SerializersCodeGen.compile(descriptor, output: :json)
        }.not_to raise_error
      end

      def descriptor_with_two_models(name:, source:, models:)
        SerializersCodeGen::Descriptor.new(
          name: "VehicleDescriptor",
          models: models,
          attributes: [SerializersCodeGen::Attribute.new(name: name, source: source)],
          method_attributes: [],
          associations: []
        )
      end

      it "S7.1 multi-class: does not raise when source is column-backed on every class in a multi-class set" do
        v = fake_ar_class(name: "Vehicle", columns: ["vin", "make"])
        c = fake_ar_class(name: "Car", columns: ["vin", "make"])
        descriptor = descriptor_with_two_models(name: :vin, source: :vin, models: [v, c])
        expect {
          SerializersCodeGen.compile(descriptor, output: :json)
        }.not_to raise_error
      end

      it "S7.1 multi-class: does not raise when source downgrades to method dispatch (column-backed on one, method-only on the other)" do
        v = fake_ar_class(name: "Vehicle", columns: ["make"], methods: %i[make])
        c = fake_ar_class(name: "Car", columns: [], methods: %i[make])
        descriptor = descriptor_with_two_models(name: :make, source: :make, models: [v, c])
        expect {
          SerializersCodeGen.compile(descriptor, output: :json)
        }.not_to raise_error
      end

      it "S7.1 multi-class: raises UnknownSourceError when source is missing on at least one class in the set; message names the class" do
        v = fake_ar_class(name: "Vehicle", columns: ["vin"], methods: %i[wheels])
        c = fake_ar_class(name: "Car", columns: ["vin"])
        descriptor = descriptor_with_two_models(name: :wheels, source: :wheels, models: [v, c])
        expect {
          SerializersCodeGen.compile(descriptor, output: :json)
        }.to raise_error(
          SerializersCodeGen::UnknownSourceError,
          "VehicleDescriptor#wheels: Attribute#source :wheels is not a column or instance method on Car."
        )
      end
    end

    describe "ArityError (S4)" do
      def descriptor_with_method_attribute(name:, body:)
        SerializersCodeGen::Descriptor.new(
          name: "PostDescriptor",
          models: nil,
          attributes: [],
          method_attributes: [SerializersCodeGen::MethodAttribute.new(name: name, body: body)],
          associations: []
        )
      end

      def descriptor_with_association_if(name:, if_callable:)
        inner = SerializersCodeGen::Descriptor.new(
          name: "InnerDescriptor", models: nil,
          attributes: [], method_attributes: [], associations: []
        )
        SerializersCodeGen::Descriptor.new(
          name: "PostDescriptor",
          models: nil,
          attributes: [],
          method_attributes: [],
          associations: [
            SerializersCodeGen::Association.new(
              name: name, kind: :has_one, descriptor: inner, if: if_callable
            )
          ]
        )
      end

      {
        3 => ->(_a, _b, _c) { :ok },
        -1 => ->(*_args) { :ok },
        -2 => ->(_a, *_rest) { :ok }
      }.each do |arity, body|
        it "raises when MethodAttribute body has arity #{arity}" do
          descriptor = descriptor_with_method_attribute(name: :likes_count, body: body)
          expect {
            SerializersCodeGen.compile(descriptor, output: :json)
          }.to raise_error(SerializersCodeGen::ArityError, /arity #{arity}/)
        end
      end

      {
        3 => ->(_a, _b, _c) { true },
        -1 => ->(*_args) { true },
        -2 => ->(_a, *_rest) { true }
      }.each do |arity, body|
        it "raises when Association if: has arity #{arity}" do
          descriptor = descriptor_with_association_if(name: :author, if_callable: body)
          expect {
            SerializersCodeGen.compile(descriptor, output: :json)
          }.to raise_error(
            SerializersCodeGen::ArityError,
            "PostDescriptor#author: Association#if has arity #{arity}; must be 0, 1, or 2."
          )
        end
      end

      {
        0 => -> { :ok },
        1 => ->(_record) { :ok },
        2 => ->(_record, _context) { :ok }
      }.each do |arity, body|
        it "compiles when MethodAttribute body has arity #{arity}" do
          descriptor = descriptor_with_method_attribute(name: :computed, body: body)
          expect {
            SerializersCodeGen.compile(descriptor, output: :json)
          }.not_to raise_error
        end
      end

      {
        0 => -> { true },
        1 => ->(_record) { true },
        2 => ->(_record, _context) { true }
      }.each do |arity, body|
        it "compiles when Association if: has arity #{arity}" do
          descriptor = descriptor_with_association_if(name: :author, if_callable: body)
          expect {
            SerializersCodeGen.compile(descriptor, output: :json)
          }.not_to raise_error
        end
      end
    end
  end

  describe "Message convention" do
    it "DescriptorError names the Field, kind, rule, and observed value (S1.3 / S1.4)" do
      expect {
        SerializersCodeGen::Attribute.new(name: "title")
      }.to raise_error(SerializersCodeGen::DescriptorError) { |err|
        expect(err.message).to include("Attribute#name")
        expect(err.message).to include("Symbol")
        expect(err.message).to include('"title"')
      }
    end

    it "NameCollisionError names the Descriptor, Field name, and rule (S9)" do
      descriptor = SerializersCodeGen::Descriptor.new(
        name: "PostDescriptor", models: nil,
        attributes: [SerializersCodeGen::Attribute.new(name: :id)],
        method_attributes: [SerializersCodeGen::MethodAttribute.new(name: :id, body: -> { "computed" })],
        associations: []
      )
      expect {
        SerializersCodeGen.compile(descriptor, output: :json)
      }.to raise_error(
        SerializersCodeGen::NameCollisionError,
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
      descriptor = SerializersCodeGen::Descriptor.new(
        name: "PostDescriptor",
        models: [klass],
        attributes: [SerializersCodeGen::Attribute.new(name: :title, source: :raw_title)],
        method_attributes: [],
        associations: []
      )
      expect {
        SerializersCodeGen.compile(descriptor, output: :json)
      }.to raise_error(
        SerializersCodeGen::UnknownSourceError,
        "PostDescriptor#title: Attribute#source :raw_title is not a column or instance method on Post."
      )
    end

    it "ArityError matches the docs/errors.md § Message convention example (S4)" do
      descriptor = SerializersCodeGen::Descriptor.new(
        name: "PostDescriptor",
        models: nil,
        attributes: [],
        method_attributes: [
          SerializersCodeGen::MethodAttribute.new(name: :likes_count, body: ->(_a, _b, _c) { :ok })
        ],
        associations: []
      )
      expect {
        SerializersCodeGen.compile(descriptor, output: :json)
      }.to raise_error(
        SerializersCodeGen::ArityError,
        "PostDescriptor#likes_count: MethodAttribute#body has arity 3; must be 0, 1, or 2."
      )
    end
  end

  describe "SKIP singleton (S1.3)" do
    it "is identity-stable via #equal?" do
      expect(SerializersCodeGen::SKIP.equal?(SerializersCodeGen::SKIP)).to be(true)
    end

    it "is frozen" do
      expect(SerializersCodeGen::SKIP).to be_frozen
    end
  end

  describe "NotImplementedError — phase-1 filters contract (S2.3 / S3.3)" do
    let(:descriptor) { Fixtures::ShallowGeneric::DESCRIPTOR }
    let(:config) { Fixtures::ShallowGeneric::CONFIG }
    let(:record) { {"id" => 1, "title" => "hi"} }

    before do
      require "shallow_generic"
    end

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:generated_class) { SerializersCodeGen.compile(descriptor, output: mode, config: config) }
        let(:instance) { generated_class.new(descriptor: descriptor) }

        it "raises NotImplementedError on serialize_one with filters: {only: [:id]}" do
          expect {
            instance.serialize_one(record, filters: {only: [:id]})
          }.to raise_error(NotImplementedError)
        end

        it "raises NotImplementedError on serialize_one with filters: {}" do
          expect {
            instance.serialize_one(record, filters: {})
          }.to raise_error(NotImplementedError)
        end

        it "does not raise on serialize_one with default filters: nil" do
          expect(instance.serialize_one(record)).not_to be_nil
        end

        it "raises NotImplementedError on serialize_many with filters: {only: [:id]}" do
          expect {
            instance.serialize_many([record], filters: {only: [:id]})
          }.to raise_error(NotImplementedError)
        end

        it "does not raise on serialize_many with default filters: nil" do
          expect(instance.serialize_many([record])).not_to be_nil
        end
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
      SerializersCodeGen::Descriptor.new(
        name: "PostDescriptor",
        models: [klass],
        attributes: [SerializersCodeGen::Attribute.new(name: :missing, source: :missing)],
        method_attributes: [],
        associations: []
      )
    end

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "NameCollisionError raises before Generator emit (S9)" do
          descriptor = SerializersCodeGen::Descriptor.new(
            name: "PostDescriptor", models: nil,
            attributes: [
              SerializersCodeGen::Attribute.new(name: :id),
              SerializersCodeGen::Attribute.new(name: :id)
            ],
            method_attributes: [], associations: []
          )
          expect {
            SerializersCodeGen.compile(descriptor, output: mode)
          }.to raise_error(SerializersCodeGen::NameCollisionError, /Attribute and Attribute share name/)
        end

        it "UnknownSourceError raises before Generator emit (S6)" do
          expect {
            SerializersCodeGen.compile(unknown_source_descriptor, output: mode)
          }.to raise_error(SerializersCodeGen::UnknownSourceError, /not a column or instance method on Post/)
        end

        it "ArityError raises before Generator emit (S4)" do
          descriptor = SerializersCodeGen::Descriptor.new(
            name: "PostDescriptor",
            models: nil,
            attributes: [],
            method_attributes: [
              SerializersCodeGen::MethodAttribute.new(name: :likes_count, body: ->(_a, _b, _c) { :ok })
            ],
            associations: []
          )
          expect {
            SerializersCodeGen.compile(descriptor, output: mode)
          }.to raise_error(SerializersCodeGen::ArityError, /MethodAttribute#body has arity 3/)
        end
      end
    end
  end
end
