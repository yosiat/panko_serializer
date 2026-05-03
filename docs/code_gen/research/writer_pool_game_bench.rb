# frozen_string_literal: true

# Game-shape pool bench — adds a `scg/json (pooled)` row to the
# game_serializer_bench.rb shape (Game with has_one :scores, has_one
# :best_player, has_many :players). Lets us see what writer pooling buys on
# a real graph instead of the simple-shape exploration in
# writer_pool_exploration.rb.
#
# Run: bundle exec ruby --yjit docs/research/writer_pool_game_bench.rb

require "active_record"
require "sqlite3"
require "oj"
require "benchmark/ips"
require "memory_profiler"

Oj.default_options = {mode: :rails, use_raw_json: true}
require "active_support/core_ext/string/starts_ends_with"
require "oj_serializers"
require "panko_serializer"

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "serializers_code_gen"

RubyVM::YJIT.enable if defined?(RubyVM::YJIT)
unless defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
  warn "WARNING: YJIT not enabled. Re-run with --yjit."
end

# ---- AR setup (mirrors game_serializer_bench.rb) ---------------------------

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :games, force: true do |t|
    t.string :name
    t.integer :high_score, default: 500
    t.integer :score, default: 0
    t.references :best_player
  end

  create_table :players, force: true do |t|
    t.string :first_name
    t.string :last_name
    t.references :game
  end
end

class Player < ActiveRecord::Base
  belongs_to :game, optional: true

  def full_name
    "#{first_name} #{last_name}"
  end
end

class Game < ActiveRecord::Base
  belongs_to :best_player, class_name: "Player", optional: true
  has_many :players

  def scores
    self
  end
end

Game.define_attribute_methods
Player.define_attribute_methods

Game.insert_all([{name: "Tetris", high_score: 1500, score: 3165}])
GAME_ID = Game.pick(:id)
Player.insert_all([
  {first_name: "Alexey", last_name: "Pajitnov", game_id: GAME_ID},
  {first_name: "Vadim", last_name: "Gerasimov", game_id: GAME_ID}
])
BEST_PLAYER_ID = Player.where(game_id: GAME_ID).order(:id).pick(:id)
Game.where(id: GAME_ID).update_all(best_player_id: BEST_PLAYER_ID)

GAME = Game.includes(:best_player, :players).find(GAME_ID)

# ---- SCG descriptors -------------------------------------------------------

PLAYER_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "PlayerSerializer",
  models: [Player],
  attributes: [
    SerializersCodeGen::Attribute.new(name: :id, source: :id),
    SerializersCodeGen::Attribute.new(name: :first_name, source: :first_name),
    SerializersCodeGen::Attribute.new(name: :last_name, source: :last_name)
  ],
  method_attributes: [
    SerializersCodeGen::MethodAttribute.new(
      name: :full_name,
      body: ->(record, _ctx) { record.full_name }
    )
  ],
  associations: []
)

SCORES_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "ScoresSerializer",
  models: [Game],
  attributes: [
    SerializersCodeGen::Attribute.new(name: :high_score, source: :high_score),
    SerializersCodeGen::Attribute.new(name: :score, source: :score)
  ],
  method_attributes: [],
  associations: []
)

GAME_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "GameSerializer",
  models: [Game],
  attributes: [
    SerializersCodeGen::Attribute.new(name: :id, source: :id),
    SerializersCodeGen::Attribute.new(name: :name, source: :name)
  ],
  method_attributes: [],
  associations: [
    SerializersCodeGen::Association.new(name: :scores, kind: :has_one, descriptor: SCORES_DESCRIPTOR),
    SerializersCodeGen::Association.new(name: :best_player, kind: :has_one, descriptor: PLAYER_DESCRIPTOR),
    SerializersCodeGen::Association.new(name: :players, kind: :has_many, descriptor: PLAYER_DESCRIPTOR)
  ]
)

# ---- Two SCG variants: shipped (fresh writer) vs pooled --------------------
# The pooled subclass overrides ONLY the public serialize_one. Nested
# composition still threads the parent writer through _write_one, so the
# nested classes need no changes (and would break if naively pooled — they'd
# .reset the parent's open frames).

SCG_JSON_FRESH_CLASS = SerializersCodeGen.compile(GAME_DESCRIPTOR, output: :json)
SCG_JSON_FRESH = SCG_JSON_FRESH_CLASS.new(descriptor: GAME_DESCRIPTOR)

SCG_JSON_POOLED_CLASS = Class.new(SCG_JSON_FRESH_CLASS) do
  def serialize_one(record, context: nil, filters: nil)
    filters = SerializersCodeGen::Filter.wrap(filters, self.class::FIELD_INDEX)
    writer = (Thread.current[:_scg_writer] ||= Oj::StringWriter.new(mode: :rails))
    writer.reset
    _write_one(record, writer, context, filters)
    result = writer.to_s
    result.chomp!
    result
  end
end
SCG_JSON_POOLED = SCG_JSON_POOLED_CLASS.new(descriptor: GAME_DESCRIPTOR)

# Output-parity guard: pooled must match fresh byte-for-byte.
fresh_out = SCG_JSON_FRESH.serialize_one(GAME)
pooled_out = SCG_JSON_POOLED.serialize_one(GAME)
abort "scg pooled diverged: #{fresh_out.inspect} vs #{pooled_out.inspect}" if fresh_out != pooled_out

# ---- Comparison targets (panko, oj_serializers — same as upstream) ---------

class PlayerPanko < Panko::Serializer
  attributes :id, :first_name, :last_name, :full_name

  def full_name
    object.full_name
  end
end

class ScoresPanko < Panko::Serializer
  attributes :high_score, :score
end

class GamePanko < Panko::Serializer
  attributes :id, :name
  has_one :scores, serializer: ScoresPanko
  has_one :best_player, serializer: PlayerPanko
  has_many :players, serializer: PlayerPanko
end

class PlayerOjJsonSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :first_name, :last_name

  attribute
  def full_name
    @object.full_name
  end
end

class ScoresOjJsonSerializer < OjSerializers::Serializer
  default_format :json
  attributes :high_score, :score
end

class GameOjJsonSerializer < OjSerializers::Serializer
  default_format :json
  attributes :id, :name
  has_one :scores, serializer: ScoresOjJsonSerializer
  has_one :best_player, serializer: PlayerOjJsonSerializer
  has_many :players, serializer: PlayerOjJsonSerializer
end

# Output parity across all four targets.
parity_outputs = {
  "scg/json (fresh)" => SCG_JSON_FRESH.serialize_one(GAME),
  "scg/json (pooled)" => SCG_JSON_POOLED.serialize_one(GAME),
  "panko" => GamePanko.new.serialize_to_json(GAME),
  "oj_serializers/json" => GameOjJsonSerializer.one(GAME).to_s
}
parsed = parity_outputs.transform_values { |s| Oj.load(s.to_s, mode: :strict) }
ref_label, ref = parsed.first
parsed.each do |label, value|
  next if label == ref_label || value == ref
  warn "JSON output mismatch: #{ref_label} vs #{label}"
  warn "  #{ref_label}: #{Oj.dump(ref)}"
  warn "  #{label}:    #{Oj.dump(value)}"
  abort "aborting bench — output shapes diverged"
end
puts "JSON output parity verified: #{parity_outputs.keys.join(", ")}"
puts "Sample: #{Oj.dump(ref)}"
puts

puts "Ruby:   #{RUBY_DESCRIPTION}"
puts "AR:     #{ActiveRecord::VERSION::STRING}"
puts "YJIT:   #{(defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?) ? "on" : "off"}"
puts

# ---- Bench helpers ---------------------------------------------------------

def measure(label, &block)
  block.call

  ips_report = Benchmark.ips do |x|
    x.config(time: 5, warmup: 2, quiet: true)
    x.report(label, &block)
  end
  entry = ips_report.entries.first
  rate = entry.stats.central_tendency
  err = entry.stats.error_percentage

  GC.disable
  mem = MemoryProfiler.report(&block)
  GC.enable
  GC.start

  rate_s = if rate >= 1_000_000 then "%.2fM" % (rate / 1_000_000)
  elsif rate >= 1_000 then "%.2fK" % (rate / 1_000)
  else "%.2f" % rate
  end

  puts "%-40s %10s i/s ±%5.2f%%  %8d allocs  %8d retained" %
    [label, rate_s, err, mem.total_allocated, mem.total_retained]
end

# ---- Benchmark -------------------------------------------------------------

rows = {
  "oj_serializers/json" => -> { GameOjJsonSerializer.one(GAME).to_s },
  "panko" => -> { GamePanko.new.serialize_to_json(GAME) },
  "scg/json (fresh, shipped)" => -> { SCG_JSON_FRESH.serialize_one(GAME) },
  "scg/json (pooled)" => -> { SCG_JSON_POOLED.serialize_one(GAME) }
}

rows.each { |label, block| measure(label, &block) }
