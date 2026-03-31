# frozen_string_literal: true

require "spec_helper"

describe Panko::Filters do
  class FiltersSpecFooSerializer < Panko::Serializer
    attributes :name, :address
  end

  class FiltersSpecMethodSerializer < Panko::Serializer
    attributes :name, :address, :computed
    def computed
      "#{object.name}-computed"
    end
  end

  class FiltersSpecHasOneSerializer < Panko::Serializer
    attributes :title
    has_one :foo, serializer: FiltersSpecFooSerializer
  end

  class FiltersSpecHasManySerializer < Panko::Serializer
    attributes :title
    has_many :foos, serializer: FiltersSpecFooSerializer
  end

  class FiltersSpecBothAssocSerializer < Panko::Serializer
    attributes :title
    has_one :bar, serializer: FiltersSpecFooSerializer
    has_many :foos, serializer: FiltersSpecFooSerializer
  end

  describe ".apply" do
    context "when options contain neither :only nor :except" do
      it "is a no-op and leaves attributes unchanged" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecFooSerializer._descriptor)
        original_attrs = descriptor.attributes.dup

        Panko::Filters.apply(descriptor, {})

        expect(descriptor.attributes).to eq(original_attrs)
      end

      it "is a no-op and leaves method_fields unchanged" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecMethodSerializer._descriptor)
        original_methods = descriptor.method_fields.dup

        Panko::Filters.apply(descriptor, {})

        expect(descriptor.method_fields).to eq(original_methods)
      end
    end

    context "with :only as an array" do
      it "keeps only the listed attributes" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecFooSerializer._descriptor)

        Panko::Filters.apply(descriptor, only: [:name])

        expect(descriptor.attributes).to contain_exactly(Panko::Attribute.create(:name))
      end

      it "results in empty attributes when no match" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecFooSerializer._descriptor)

        Panko::Filters.apply(descriptor, only: [:nonexistent])

        expect(descriptor.attributes).to be_empty
      end
    end

    context "with :except as an array" do
      it "removes the listed attributes" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecFooSerializer._descriptor)

        Panko::Filters.apply(descriptor, except: [:name])

        expect(descriptor.attributes).to contain_exactly(Panko::Attribute.create(:address))
      end

      it "keeps all attributes when no match" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecFooSerializer._descriptor)

        Panko::Filters.apply(descriptor, except: [:nonexistent])

        expect(descriptor.attributes).to match_array([
          Panko::Attribute.create(:name),
          Panko::Attribute.create(:address)
        ])
      end
    end

    context "with :only as a hash with :instance key" do
      it "filters instance attributes using :instance value" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecFooSerializer._descriptor)

        Panko::Filters.apply(descriptor, only: {instance: [:name]})

        expect(descriptor.attributes).to contain_exactly(Panko::Attribute.create(:name))
      end

      it "filters nested has_one association attributes" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecHasOneSerializer._descriptor)

        Panko::Filters.apply(descriptor, only: {instance: [:title, :foo], foo: [:name]})

        expect(descriptor.attributes).to contain_exactly(Panko::Attribute.create(:title))
        expect(descriptor.has_one_associations.size).to eq(1)
        foo_assoc = descriptor.has_one_associations.first
        expect(foo_assoc.name_sym).to eq(:foo)
        expect(foo_assoc.descriptor.attributes).to contain_exactly(Panko::Attribute.create(:name))
      end

      it "filters nested has_many association attributes" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecHasManySerializer._descriptor)

        Panko::Filters.apply(descriptor, only: {instance: [:title, :foos], foos: [:address]})

        expect(descriptor.attributes).to contain_exactly(Panko::Attribute.create(:title))
        expect(descriptor.has_many_associations.size).to eq(1)
        foos_assoc = descriptor.has_many_associations.first
        expect(foos_assoc.name_sym).to eq(:foos)
        expect(foos_assoc.descriptor.attributes).to contain_exactly(Panko::Attribute.create(:address))
      end
    end

    context "with :except as a hash with :instance key" do
      it "removes instance attributes listed under :instance" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecFooSerializer._descriptor)

        Panko::Filters.apply(descriptor, except: {instance: [:name]})

        expect(descriptor.attributes).to contain_exactly(Panko::Attribute.create(:address))
      end

      it "removes nested has_one association attributes" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecHasOneSerializer._descriptor)

        Panko::Filters.apply(descriptor, except: {foo: [:address]})

        expect(descriptor.has_one_associations.size).to eq(1)
        foo_assoc = descriptor.has_one_associations.first
        expect(foo_assoc.descriptor.attributes).to contain_exactly(Panko::Attribute.create(:name))
      end

      it "removes nested has_many association attributes" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecHasManySerializer._descriptor)

        Panko::Filters.apply(descriptor, except: {foos: [:name]})

        expect(descriptor.has_many_associations.size).to eq(1)
        foos_assoc = descriptor.has_many_associations.first
        expect(foos_assoc.descriptor.attributes).to contain_exactly(Panko::Attribute.create(:address))
      end
    end

    context "with method_fields" do
      it "filters method_fields with :only array" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecMethodSerializer._descriptor)

        Panko::Filters.apply(descriptor, only: [:computed])

        expect(descriptor.attributes).to be_empty
        expect(descriptor.method_fields).to contain_exactly(Panko::Attribute.create(:computed))
      end

      it "filters method_fields with :except array" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecMethodSerializer._descriptor)

        Panko::Filters.apply(descriptor, except: [:computed])

        expect(descriptor.method_fields).to be_empty
        expect(descriptor.attributes).to match_array([
          Panko::Attribute.create(:name),
          Panko::Attribute.create(:address)
        ])
      end
    end

    context "with has_one association filtering" do
      it "keeps listed has_one association with flat :only" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecHasOneSerializer._descriptor)

        Panko::Filters.apply(descriptor, only: %i[title foo])

        expect(descriptor.has_one_associations.size).to eq(1)
        expect(descriptor.has_one_associations.first.name_sym).to eq(:foo)
      end

      it "removes has_one association with flat :except" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecHasOneSerializer._descriptor)

        Panko::Filters.apply(descriptor, except: [:foo])

        expect(descriptor.has_one_associations).to be_empty
      end
    end

    context "with has_many association filtering" do
      it "keeps listed has_many association with flat :only" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecHasManySerializer._descriptor)

        Panko::Filters.apply(descriptor, only: %i[title foos])

        expect(descriptor.has_many_associations.size).to eq(1)
        expect(descriptor.has_many_associations.first.name_sym).to eq(:foos)
      end

      it "removes has_many association with flat :except" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecHasManySerializer._descriptor)

        Panko::Filters.apply(descriptor, except: [:foos])

        expect(descriptor.has_many_associations).to be_empty
      end
    end

    context "input mutation" do
      it "does not mutate the original descriptor association arrays" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecBothAssocSerializer._descriptor)
        original_has_one = descriptor.has_one_associations.dup
        original_has_many = descriptor.has_many_associations.dup

        Panko::Filters.apply(descriptor, only: [:title])

        expect(original_has_one).not_to be_empty
        expect(original_has_many).not_to be_empty
      end
    end

    context "with empty hash filter" do
      it "treats only: {} as a no-op" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecFooSerializer._descriptor)
        original_attrs = descriptor.attributes.dup

        Panko::Filters.apply(descriptor, only: {})

        expect(descriptor.attributes).to eq(original_attrs)
      end

      it "treats except: {} as a no-op" do
        descriptor = Panko::SerializationDescriptor.duplicate(FiltersSpecFooSerializer._descriptor)
        original_attrs = descriptor.attributes.dup

        Panko::Filters.apply(descriptor, except: {})

        expect(descriptor.attributes).to eq(original_attrs)
      end
    end
  end
end
