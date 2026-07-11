# frozen_string_literal: true

require_relative "support/benchmark"

# Datetime-heavy shape: four datetime columns next to id/name, batch of 50.
# Owns its own schema (adding datetimes to bench_posts would change every
# other scenario's record width). Exercises the raw-string datetime fast
# path (DateTimeFormat splice over read_attribute_before_type_cast) on the
# specialized rows vs the type-cast + as_json/Oj path on the generic rows.
#
# Run (YJIT — the production target):
#   bundle exec ruby --yjit benchmarks/datetimes.rb

ActiveRecord::Schema.define do
  create_table :bench_events, force: true do |t|
    t.string :name
    t.datetime :starts_at
    t.datetime :ends_at
    t.timestamps
  end
end

module Bench
  class Event < ActiveRecord::Base
    self.table_name = "bench_events"
  end
end

Bench::Event.define_attribute_methods

EVENT_COUNT = 50
now = Time.now.utc
Bench::Event.insert_all(
  (1..EVENT_COUNT).map do |i|
    {
      name: "Event #{i}",
      starts_at: now + i * 3600,
      ends_at: now + i * 7200,
      created_at: now,
      updated_at: now
    }
  end
)
EVENTS = Bench::Event.order(:id).to_a

EVENT_DESCRIPTOR = Panko::CodeGen::Descriptor.new(
  name: "EventSerializer",
  model: Bench::Event,
  attributes: %i[id name starts_at ends_at created_at updated_at].map do |name|
    Panko::CodeGen::Attribute.new(name: name, source: name)
  end,
  method_attributes: [],
  associations: []
)

SCG_JSON_EVENTS = Panko::CodeGen.compile(EVENT_DESCRIPTOR, output: :json).new(descriptor: EVENT_DESCRIPTOR)
SCG_HASH_EVENTS = Panko::CodeGen.compile(EVENT_DESCRIPTOR, output: :hash).new(descriptor: EVENT_DESCRIPTOR)

class EventPankoSerializer < Panko::Serializer
  attributes :id, :name, :starts_at, :ends_at, :created_at, :updated_at
end

class EventOjSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :name, :starts_at, :ends_at, :created_at, :updated_at
end

# --- Output-parity guard --------------------------------------------------

parity = {
  "serializers_code_gen/json" => SCG_JSON_EVENTS.serialize_many(EVENTS),
  "serializers_code_gen/hash" => Oj.dump(SCG_HASH_EVENTS.serialize_many(EVENTS), mode: :rails),
  "panko/json" => Panko::ArraySerializer.new(EVENTS, each_serializer: EventPankoSerializer).to_json,
  "panko/object" => Oj.dump(Panko::ArraySerializer.new(EVENTS, each_serializer: EventPankoSerializer).to_a, mode: :rails),
  "oj_serializers/json" => EventOjSerializer.many(EVENTS).to_s
}
reference_label, reference = parity.first
parity.each do |label, value|
  next if label == reference_label || value.to_s.chomp == reference
  warn "output mismatch between #{reference_label} and #{label}:"
  warn "  #{reference_label}: #{reference[0, 200]}"
  warn "  #{label}: #{value.to_s[0, 200]}"
  abort "aborting bench — output diverged"
end
puts "Output parity verified (byte-level): #{parity.keys.join(", ")}"
puts "Sample: #{Oj.load(reference).first}"
puts

# --- Scenario rows --------------------------------------------------------

rows = {
  "serializers_code_gen/json" => -> { SCG_JSON_EVENTS.serialize_many(EVENTS) },
  "serializers_code_gen/hash" => -> { SCG_HASH_EVENTS.serialize_many(EVENTS) },
  "panko/json" => -> { Panko::ArraySerializer.new(EVENTS, each_serializer: EventPankoSerializer).to_json },
  "panko/object" => -> { Panko::ArraySerializer.new(EVENTS, each_serializer: EventPankoSerializer).to_a },
  "oj_serializers/json" => -> { EventOjSerializer.many(EVENTS).to_s }
}

rows.each do |row_label, row_callable|
  next if BENCHMARK_CONFIG.target && !row_label.downcase.include?(BENCHMARK_CONFIG.target.downcase)
  benchmark("Datetimes size=#{EVENT_COUNT}/#{row_label}", &row_callable)
end
