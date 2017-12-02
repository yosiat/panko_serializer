# frozen_string_literal: true
require_relative "./benchmarking_support"
require "rails"
require "active_support"

require "panko_serializer"

def generate_attributes(count)
  (1..count).map { |i| "attr_#{i}".to_sym }
end

class LeafASerializer < Panko::Serializer
  attributes *generate_attributes(5)
end

class LeafBSerializer < Panko::Serializer
  attributes *generate_attributes(6)
end

class ChildrenSerializer < Panko::Serializer
  attributes *generate_attributes(28)

  has_one :leaf_a, serializer: LeafASerializer
  has_one :leaf_b, serializer: LeafBSerializer

  def attr_1
  end

  def attr_2
  end

  def attr_3
  end

  def attr_4
  end

  def attr_5
  end
end

class ParentSerializer < Panko::Serializer
  attributes *generate_attributes(46)

  has_many :children, serializer: ChildrenSerializer


  def attr_1
  end

  def attr_2
  end

  def attr_3
  end

  def attr_4
  end
end

attrs = generate_attributes(21)
attrs << :children
filters = {
  instance: attrs,
  children: generate_attributes(11)
}
Benchmark.run("NoFilters") do
  Panko::SerializationDescriptor.build(ParentSerializer)
end

Benchmark.run("Attribute") do
  Panko::SerializationDescriptor.build(ParentSerializer, only: [:children])
end

Benchmark.run("AssociationFilters") do
  Panko::SerializationDescriptor.build(ParentSerializer, only: filters)
end
