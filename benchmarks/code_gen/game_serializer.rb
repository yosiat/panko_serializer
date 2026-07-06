# frozen_string_literal: true

require_relative "support/benchmark"

# Single-record GameSerializer benchmark — direct port of
# https://github.com/ElMassimo/oj_serializers/blob/main/benchmarks/game_serializer_benchmark.rb
# with scg added alongside oj_serializers and panko. Owns its own Game/Player
# schema (with the upstream `scores` alias) so absolute numbers stay
# comparable to oj_serializers' published run; reuses the shared harness's
# benchmark() for ips + allocs + retained output and env knobs
# (IPS_TIME / IPS_WARMUP / BENCH / TARGET).
#
# Run (YJIT — the production target):
#   bundle exec ruby --yjit benchmarks/game_serializer.rb

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

  # Mirrors `Game.prepend Module.new { def scores; self; end }` from the
  # source benchmark — has_one :scores walks back to the game itself so the
  # Scores serializer reads high_score/score off the game's own row.
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

# --- SCG ------------------------------------------------------------------

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

SCG_JSON = SerializersCodeGen.compile(GAME_DESCRIPTOR, output: :json).new(descriptor: GAME_DESCRIPTOR)
# Symbol keys for the hash row: Symbol#hash is cached, so Hash construction
# is ~9–11% faster than with String keys (see docs/deferred.md § Hash-mode
# default key type). The parity check below normalizes both rows through
# Oj.load(mode: :strict), which coerces Symbol/String keys to Strings, so
# the byte-parity assertion still holds.
SCG_HASH = SerializersCodeGen.compile(
  GAME_DESCRIPTOR,
  output: :hash,
  config: SerializersCodeGen::Config.new(hash_output_key_type: :symbol)
).new(descriptor: GAME_DESCRIPTOR)

# --- SCG parent_class dispatch -------------------------------------------
# Symbol-body MethodAttribute under parent_class: PlayerSerializerBase —
# the S18 direct-dispatch shape Panko relies on once scg is absorbed (per
# docs/merging-into-panko.md § Generated Class subclasses the user's Panko
# serializer). The Generated Class becomes a subclass of
# PlayerSerializerBase, @object / @context / @scope are written to ivars
# at the top of _write_one / _to_hash, and `body: :full_name` dispatches
# via direct method call on self. Only the Player descriptor changes
# shape — Scores and Game have no MethodAttributes, so flipping their
# parent_class would only swap the subclass line without exercising
# dispatch.

class PlayerSerializerBase
  def full_name
    "#{@object.first_name} #{@object.last_name}"
  end
end

PLAYER_PARENT_CLASS_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "PlayerParentClassSerializer",
  models: [Player],
  parent_class: PlayerSerializerBase,
  attributes: PLAYER_DESCRIPTOR.attributes,
  method_attributes: [
    SerializersCodeGen::MethodAttribute.new(name: :full_name, body: :full_name)
  ],
  associations: []
)

GAME_PARENT_CLASS_DESCRIPTOR = SerializersCodeGen::Descriptor.new(
  name: "GameParentClassSerializer",
  models: [Game],
  attributes: GAME_DESCRIPTOR.attributes,
  method_attributes: [],
  associations: [
    SerializersCodeGen::Association.new(name: :scores, kind: :has_one, descriptor: SCORES_DESCRIPTOR),
    SerializersCodeGen::Association.new(name: :best_player, kind: :has_one, descriptor: PLAYER_PARENT_CLASS_DESCRIPTOR),
    SerializersCodeGen::Association.new(name: :players, kind: :has_many, descriptor: PLAYER_PARENT_CLASS_DESCRIPTOR)
  ]
)

SCG_JSON_PARENT_CLASS = SerializersCodeGen.compile(GAME_PARENT_CLASS_DESCRIPTOR, output: :json).new(descriptor: GAME_PARENT_CLASS_DESCRIPTOR)
SCG_HASH_PARENT_CLASS = SerializersCodeGen.compile(
  GAME_PARENT_CLASS_DESCRIPTOR,
  output: :hash,
  config: SerializersCodeGen::Config.new(hash_output_key_type: :symbol)
).new(descriptor: GAME_PARENT_CLASS_DESCRIPTOR)

# --- Panko ----------------------------------------------------------------

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

# --- oj_serializers — two trios ------------------------------------------
# `default_format :json` makes `Serializer.one(record)` return an
# `Oj::StringWriter` whose `.to_s` materializes a JSON String in one
# dispatch — the apples-to-apples shape against panko's `serialize_to_json`
# and scg's `serialize_one`. Without it the row would pay an extra `Oj.dump`
# per call (or worse, return an Array#inspect for collection variants).
# Pinned on every nested class for symmetry — removes the foot-gun where a
# hash-mode nested ends up under a json-mode parent.
#
# See https://github.com/ElMassimo/oj_serializers#writing-to-json.

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

class PlayerOjHashSerializer < OjSerializers::Serializer
  attributes :id, :first_name, :last_name

  attribute
  def full_name
    @object.full_name
  end
end

class ScoresOjHashSerializer < OjSerializers::Serializer
  attributes :high_score, :score
end

class GameOjHashSerializer < OjSerializers::Serializer
  attributes :id, :name
  has_one :scores, serializer: ScoresOjHashSerializer
  has_one :best_player, serializer: PlayerOjHashSerializer
  has_many :players, serializer: PlayerOjHashSerializer
end

# --- Output-parity guard --------------------------------------------------

parity_outputs = {
  "serializers_code_gen/json" => SCG_JSON.serialize_one(GAME),
  "serializers_code_gen/hash" => Oj.dump(SCG_HASH.serialize_one(GAME)),
  "serializers_code_gen/json[parent_class]" => SCG_JSON_PARENT_CLASS.serialize_one(GAME),
  "serializers_code_gen/hash[parent_class]" => Oj.dump(SCG_HASH_PARENT_CLASS.serialize_one(GAME)),
  "panko/json" => GamePanko.new.serialize_to_json(GAME),
  "oj_serializers/json" => GameOjJsonSerializer.one(GAME).to_s,
  "oj_serializers/hash" => Oj.dump(GameOjHashSerializer.one(GAME))
}
parsed = parity_outputs.transform_values { |s| Oj.load(s.to_s, mode: :strict) }
reference_label, reference = parsed.first
parsed.each do |label, value|
  next if label == reference_label
  next if value == reference
  warn "JSON output mismatch between #{reference_label} and #{label}:"
  warn "  #{reference_label}: #{Oj.dump(reference)}"
  warn "  #{label}: #{Oj.dump(value)}"
  abort "aborting bench — output shapes diverged"
end
puts "JSON output parity verified: #{parity_outputs.keys.join(", ")}"
puts "Sample: #{Oj.dump(reference)}"
puts

# --- Scenario rows --------------------------------------------------------

rows = {
  "serializers_code_gen/json" => -> { SCG_JSON.serialize_one(GAME) },
  "serializers_code_gen/hash" => -> { SCG_HASH.serialize_one(GAME) },
  "serializers_code_gen/json[parent_class]" => -> { SCG_JSON_PARENT_CLASS.serialize_one(GAME) },
  "serializers_code_gen/hash[parent_class]" => -> { SCG_HASH_PARENT_CLASS.serialize_one(GAME) },
  "panko/json" => -> { GamePanko.new.serialize_to_json(GAME) },
  "oj_serializers/json" => -> { GameOjJsonSerializer.one(GAME).to_s },
  "oj_serializers/hash" => -> { GameOjHashSerializer.one(GAME) }
}

rows.each do |row_label, row_callable|
  next if BENCHMARK_CONFIG.target && !row_label.downcase.include?(BENCHMARK_CONFIG.target.downcase)
  benchmark("GameSerializer/#{row_label}", &row_callable)
end
