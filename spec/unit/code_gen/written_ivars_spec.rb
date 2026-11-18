# frozen_string_literal: true

require "spec_helper"

# Panko::Serializer and everything an app loads into its ancestors are scanned too. A
# reflective call there would put every serializer on the slower all-ivars sweep.
describe Panko::CodeGen::Generators::WrittenIvars do
  it "finds nothing in a serializer whose methods only read" do
    serializer_class = Class.new(Panko::Serializer) do
      attributes :name, :label

      def label
        "#{object.name} #{context} #{scope}"
      end
    end

    expect(described_class.of(serializer_class)).to eq({})
  end
end
