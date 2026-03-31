# frozen_string_literal: true

begin
  require "active_support"
  require "active_support/rails"
  require "active_model/attribute_set/builder"

  class ActiveModel::AttributeSet
    def _panko_attributes_hash
      @attributes
    end

    def _panko_types
      @types
    end

    def _panko_additional_types
      @additional_types
    end

    def _panko_values
      @values
    end
  end

  class ActiveModel::LazyAttributeSet
    def _panko_attributes_hash
      @attributes
    end

    def _panko_types
      @types
    end

    def _panko_additional_types
      @additional_types
    end

    def _panko_values
      @values
    end
  end
rescue => e
  puts "FAILED to patch ActiveModel::LazyAttributeSet #{e}"
  raise e
end

module Panko::Impl::AttributesWriter::ActiveRecord
  begin
    require "active_record"

    class ActiveRecord::Base
      def _panko_attributes
        @attributes
      end
    end

    if defined?(::ActiveRecord::Result::IndexedRow)
      class ::ActiveRecord::Result::IndexedRow
        def _panko_column_indexes
          @column_indexes
        end

        def _panko_row
          @row
        end
      end

      PANKO_INDEX_ROW_DEFINED = true
    else
      PANKO_INDEX_ROW_DEFINED = false
    end
  rescue
    PANKO_INDEX_ROW_DEFINED = false
  end

  EMPTY_HASH = {}.freeze
end
