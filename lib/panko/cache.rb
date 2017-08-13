# frozen_string_literal: true
require "concurrent"


module Panko
  # Serialer Descriptor Cache
  class Cache
    def initialize
      @_cache = Concurrent::Map.new
    end

    def fetch(serializer_const, options)
      serializer_key = build_key(serializer_const, options[:only], options[:except])
      serializer = @_cache.compute_if_absent(serializer_key) {
        SerializationDescriptorBuilder.build(serializer_const,
                                             only: options.fetch(:only, []),
                                             except: options.fetch(:except, [])
                                            )
      }

      serializer
    end

    private

    #
    # Create key based on what we define unique serializer
    #
    def build_key(serializer_const, only, except)
      [serializer_const, only, except].hash
    end
  end

  CACHE = Panko::Cache.new
end
