# frozen_string_literal: true

require "spec_helper"

RSpec.describe Panko::AttributesWriter::ActiveRecordWriter do
  let(:active_record_writer) { described_class.new }
  let(:writer) { double("writer") }

  describe "#write_attributes" do
    context "with real ActiveRecord objects" do
      before do
        # Create a real ActiveRecord model for testing using Temping
        Temping.create :test_user do
          with_columns do |t|
            t.string :name
            t.integer :age
            t.boolean :active
            t.datetime :created_at
            t.json :metadata
          end
        end
      end

      it "reads attributes from ActiveRecord object" do
        user = TestUser.create!(name: "John Doe", age: 30, active: true)
        attribute = Panko::Attribute.create("name")

        expect(writer).to receive(:push_value).with("John Doe", "name")

        active_record_writer.write_attributes(user, [attribute], writer)
      end

      it "handles multiple attributes" do
        user = TestUser.create!(name: "Jane Doe", age: 25, active: false)
        name_attr = Panko::Attribute.create("name")
        age_attr = Panko::Attribute.create("age")

        expect(writer).to receive(:push_value).with("Jane Doe", "name")
        expect(writer).to receive(:push_value).with(25, "age")

        active_record_writer.write_attributes(user, [name_attr, age_attr], writer)
      end

      it "handles boolean attributes" do
        user = TestUser.create!(name: "Test User", active: true)
        active_attr = Panko::Attribute.create("active")

        expect(writer).to receive(:push_value).with(true, "active")

        active_record_writer.write_attributes(user, [active_attr], writer)
      end

      it "handles datetime attributes" do
        user = TestUser.create!(name: "Test User")
        created_attr = Panko::Attribute.create("created_at")

        expect(writer).to receive(:push_value).with(an_instance_of(Time), "created_at")

        active_record_writer.write_attributes(user, [created_attr], writer)
      end

      it "handles JSON attributes" do
        metadata = {"role" => "admin", "permissions" => ["read", "write"]}
        user = TestUser.create!(name: "Admin User", metadata: metadata)
        metadata_attr = Panko::Attribute.create("metadata")

        # JSON attributes get type-cast, so we expect the serialized string
        expect(writer).to receive(:push_value).with(metadata.to_json, "metadata")

        active_record_writer.write_attributes(user, [metadata_attr], writer)
      end

      it "handles nil attributes gracefully" do
        user = TestUser.create!(name: "Test User", age: nil)
        age_attr = Panko::Attribute.create("age")

        expect(writer).to receive(:push_value).with(nil, "age")

        active_record_writer.write_attributes(user, [age_attr], writer)
      end

      it "handles missing attributes gracefully" do
        user = TestUser.create!(name: "Test User")
        missing_attr = Panko::Attribute.create("missing_attribute")

        expect(writer).to receive(:push_value).with(nil, "missing_attribute")

        active_record_writer.write_attributes(user, [missing_attr], writer)
      end
    end

    context "with ActiveRecord::Result::IndexedRow (Rails 8)" do
      before do
        skip "ActiveRecord::Result::IndexedRow not available in test environment" unless defined?(ActiveRecord::Result::IndexedRow)
      end

      it "handles indexed row optimization for Rails 8" do
        # Create a mock indexed row that mimics the real structure
        indexed_row = double("indexed_row")
        allow(indexed_row).to receive(:is_a?).with(ActiveRecord::Result::IndexedRow).and_return(true)
        allow(indexed_row).to receive(:instance_variable_get).with(:@column_indexes).and_return({"name" => 0, "age" => 1})
        allow(indexed_row).to receive(:instance_variable_get).with(:@row).and_return(["John Doe", 30])

        # Create a mock attributes set
        attributes_set = double("attributes_set")
        allow(attributes_set).to receive(:instance_variable_get).with(:@attributes).and_return({})
        allow(attributes_set).to receive(:instance_variable_get).with(:@types).and_return({})
        allow(attributes_set).to receive(:instance_variable_get).with(:@additional_types).and_return({})
        allow(attributes_set).to receive(:instance_variable_get).with(:@values).and_return(indexed_row)

        # Create a mock ActiveRecord object
        object = double("active_record_object")
        allow(object).to receive(:class).and_return(double("record_class"))
        allow(object).to receive(:instance_variable_get).with(:@attributes).and_return(attributes_set)

        name_attr = Panko::Attribute.create("name")
        age_attr = Panko::Attribute.create("age")

        expect(writer).to receive(:push_value).with("John Doe", "name")
        expect(writer).to receive(:push_value).with(30, "age")

        active_record_writer.write_attributes(object, [name_attr, age_attr], writer)
      end
    end

    context "with different attribute sources" do
      it "prioritizes attributes_hash over values" do
        # Create a mock attributes set with both attributes_hash and values
        attributes_set = double("attributes_set")

        # Mock attributes_hash with metadata
        attribute_metadata = double("attribute_metadata")
        allow(attribute_metadata).to receive(:instance_variable_get).with(:@value_before_type_cast).and_return("Hash Value")
        allow(attribute_metadata).to receive(:instance_variable_get).with(:@type).and_return(nil)

        attributes_hash = {"name" => attribute_metadata}
        allow(attributes_set).to receive(:instance_variable_get).with(:@attributes).and_return(attributes_hash)
        allow(attributes_set).to receive(:instance_variable_get).with(:@types).and_return({})
        allow(attributes_set).to receive(:instance_variable_get).with(:@additional_types).and_return({})
        allow(attributes_set).to receive(:instance_variable_get).with(:@values).and_return({"name" => "Values Value"})

        object = double("active_record_object")
        allow(object).to receive(:class).and_return(double("record_class"))
        allow(object).to receive(:instance_variable_get).with(:@attributes).and_return(attributes_set)

        name_attr = Panko::Attribute.create("name")

        # Should use the value from attributes_hash, not values
        expect(writer).to receive(:push_value).with("Hash Value", "name")

        active_record_writer.write_attributes(object, [name_attr], writer)
      end

      it "handles type resolution from additional_types" do
        attributes_set = double("attributes_set")
        allow(attributes_set).to receive(:instance_variable_get).with(:@attributes).and_return({})
        allow(attributes_set).to receive(:instance_variable_get).with(:@types).and_return({})

        # Mock a proper ActiveRecord type object
        string_type = double("string_type")
        allow(string_type).to receive(:deserialize).with("test_value").and_return("test_value")
        allow(attributes_set).to receive(:instance_variable_get).with(:@additional_types).and_return({"name" => string_type})
        allow(attributes_set).to receive(:instance_variable_get).with(:@values).and_return({"name" => "test_value"})

        object = double("active_record_object")
        allow(object).to receive(:class).and_return(double("record_class"))
        allow(object).to receive(:instance_variable_get).with(:@attributes).and_return(attributes_set)

        name_attr = Panko::Attribute.create("name")

        expect(writer).to receive(:push_value).with("test_value", "name")

        active_record_writer.write_attributes(object, [name_attr], writer)
      end

      it "handles type resolution from types" do
        attributes_set = double("attributes_set")
        allow(attributes_set).to receive(:instance_variable_get).with(:@attributes).and_return({})

        # Mock a proper ActiveRecord type object
        integer_type = double("integer_type")
        allow(integer_type).to receive(:deserialize).with("42").and_return(42)
        allow(attributes_set).to receive(:instance_variable_get).with(:@types).and_return({"name" => integer_type})
        allow(attributes_set).to receive(:instance_variable_get).with(:@additional_types).and_return({})
        allow(attributes_set).to receive(:instance_variable_get).with(:@values).and_return({"name" => "42"})

        object = double("active_record_object")
        allow(object).to receive(:class).and_return(double("record_class"))
        allow(object).to receive(:instance_variable_get).with(:@attributes).and_return(attributes_set)

        name_attr = Panko::Attribute.create("name")

        expect(writer).to receive(:push_value).with(42, "name")

        active_record_writer.write_attributes(object, [name_attr], writer)
      end
    end

    context "edge cases" do
      it "handles object without attributes" do
        object = double("active_record_object")
        allow(object).to receive(:class).and_return(double("record_class"))
        allow(object).to receive(:instance_variable_get).with(:@attributes).and_return(nil)

        name_attr = Panko::Attribute.create("name")

        expect(writer).to receive(:push_value).with(nil, "name")

        active_record_writer.write_attributes(object, [name_attr], writer)
      end

      it "handles empty attributes set" do
        attributes_set = double("attributes_set")
        allow(attributes_set).to receive(:instance_variable_get).with(:@attributes).and_return({})
        allow(attributes_set).to receive(:instance_variable_get).with(:@types).and_return({})
        allow(attributes_set).to receive(:instance_variable_get).with(:@additional_types).and_return({})
        allow(attributes_set).to receive(:instance_variable_get).with(:@values).and_return({})

        object = double("active_record_object")
        allow(object).to receive(:class).and_return(double("record_class"))
        allow(object).to receive(:instance_variable_get).with(:@attributes).and_return(attributes_set)

        name_attr = Panko::Attribute.create("name")

        expect(writer).to receive(:push_value).with(nil, "name")

        active_record_writer.write_attributes(object, [name_attr], writer)
      end
    end
  end
end
