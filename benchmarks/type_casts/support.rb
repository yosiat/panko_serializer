# frozen_string_literal: true
require "active_record"
require "active_record/connection_adapters/postgresql_adapter"
require "active_model"
require "active_support/all"
require "pg"


require_relative "../benchmarking_support"
require_relative "../../lib/panko/panko_serializer"

def assert(type_name, from, to)
  raise "#{type_name} - #{from.class} is not equals to #{to.class}" unless from.to_json == to.to_json
end

Time.zone = "UTC"
