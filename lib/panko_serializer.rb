# frozen_string_literal: true

require "panko/version"
require "panko/configuration"
require "panko/attribute"
require "panko/association"
require "panko/serializer"
require "panko/array_serializer"
require "panko/response"
require "panko/serializer_resolver"
require "panko/object_writer"

# C Extension
require "oj"
require "panko/panko_serializer"

module Panko
  extend self

  # Public: Configure Panko.
  #
  #   Panko.configure do |config|
  #     config.key_type = 'camelCase'
  #   end
  #
  def configure
    yield configuration
  end

  # Public: Returns Panko::Configuration instance.
  def configuration
    @configuration ||= Configuration.new
  end
end
