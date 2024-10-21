module Panko::Impl
  class AttributesWriter
    def self.create(object)
      if defined?(ActiveRecord::Base) && object.is_a?(ActiveRecord::Base)
        return ActiveRecordWriter.new
      end

      if object.is_a?(Hash)
        return HashWriter.new
      end

      PlainWriter.new
    end

    class ActiveRecordWriter
      def write_attributes(object, descriptor, writer)
        Panko._sd_set_writer(descriptor, object)
        Panko._write_attributes(object, descriptor, writer)
      end
    end

    class HashWriter
      def write_attributes(object, descriptor, writer)
        descriptor.attributes.each do |attr|
          value = object[attr.name]
          writer.push_value(value, attr.name_for_serialization)
        end
      end
    end

    class PlainWriter
      def write_attributes(object, descriptor, writer)
        descriptor.attributes.each do |attr|
          value = object.public_send(attr.name_sym)
          writer.push_value(value, attr.name_for_serialization)
        end
      end
    end
  end
end
