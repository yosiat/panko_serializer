# frozen_string_literal: true

require "active_record"
require "active_record/connection_adapters/postgresql_adapter"
require "active_model"
require "active_support/all"
require "pg"
require "oj"

require_relative "../benchmarking_support"
require_relative "../../lib/panko_serializer"

def assert(type_name, from, to)
  raise "#{type_name} - #{from.class} is not equals to #{to.class}" unless from.to_json == to.to_json
end

def check_if_exists(module_name)
  mod = begin
    module_name.constantize
  rescue
    nil
  end
  return true if mod
  return false unless mod
end

Time.zone = "UTC"
