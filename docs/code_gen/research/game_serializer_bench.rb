# frozen_string_literal: true

# Single-record GameSerializer benchmark — direct port of
# https://github.com/ElMassimo/oj_serializers/blob/main/benchmarks/game_serializer_benchmark.rb
# with scg added alongside oj_serializers and panko.
#
# The original benchmark serializes a single Game with one nested has_one
# (scores → self), one nested has_one (best_player), and a has_many
# (players). This script keeps that exact shape so absolute numbers stay
# comparable to the upstream run, and verifies that all three libraries
# produce byte-identical JSON before the bench starts.
#
# Run (YJIT — the production target):
#   bundle exec ruby --yjit game_serializer_bench.rb
#
# Ruby 4.0.2 is assumed (mise.toml pins it). The script warns if YJIT isn't
# enabled.

require "active_record"
require "sqlite3"
require "oj"
require "benchmark/ips"

# oj_serializers/setup.rb auto-loads `rails` unless `Oj.default_options[:use_raw_json]`
# is set beforehand. Pre-set so we don't drag in Rails just to load the
# comparison target.
Oj.default_options = {mode: :rails, use_raw_json: true}
require "active_support/core_ext/string/starts_ends_with"
require "oj_serializers"
require "panko_serializer"

# Local scg, loaded from the repo's lib/. This script lives at
# docs/research/, so ../../lib resolves to the gem's lib/.
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "serializers_code_gen"

RubyVM::YJIT.enable if defined?(RubyVM::YJIT)

# ---- AR setup ---------------------------------------------------------------

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

  # Mirrors `Game.prepend Module.new { def scores; self; end }` from the
  # source benchmark — has_one :scores walks back to the game itself so the
  # Scores serializer reads high_score/score off the game's own row.
  def scores
    self
  end
end

Game.define_attribute_methods
Player.define_attribute_methods

# ---- Fixture ---------------------------------------------------------------

Game.insert_all([{name: "Tetris", high_score: 1500, score: 3165}])
GAME_ID = Game.pick(:id)
Player.insert_all([
  {first_name: "Alexey", last_name: "Pajitnov", game_id: GAME_ID},
  {first_name: "Vadim", last_name: "Gerasimov", game_id: GAME_ID}
])
BEST_PLAYER_ID = Player.where(game_id: GAME_ID).order(:id).pick(:id)
Game.where(id: GAME_ID).update_all(best_player_id: BEST_PLAYER_ID)

GAME = Game.includes(:best_player, :players).find(GAME_ID)

# ---- SCG ------------------------------------------------------------------

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

# ---- Panko ----------------------------------------------------------------

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

# ---- oj_serializers --------------------------------------------------------
# Two trios — one with `default_format :json` for the json row, one with the
# default :hash format for the hash row. Without the split, the upstream
# `Oj.dump(GameOjSerializer.one_as_json(GAME))` shape paid an extra `Oj.dump`
# dispatch the other JSON targets don't (panko's `serialize_to_json` and
# scg's `serialize_one` both produce a JSON String in one call), biasing the
# comparison. With `default_format :json`, the canonical user shape is
# `Serializer.one(record)` → returns an `Oj::StringWriter`; calling `.to_s`
# materializes the buffer to a JSON String for parity with the other rows
# without going through `Oj.dump`.
#
# `default_format` is per-class and inherited, so each level of the
# Game→scores/best_player/players graph needs its own pair. Nested
# composition itself doesn't need `default_format :json` (parents always
# call `child.write_one(writer, ...)` against the shared writer regardless),
# but pinning the shortcut on every class keeps the two trios symmetrical
# and makes it impossible to accidentally cross-wire a hash-mode parent to a
# json-mode child or vice versa.
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

# ---- Output-parity check --------------------------------------------------

parity_outputs = {
  "scg/json" => SCG_JSON.serialize_one(GAME),
  "panko" => GamePanko.new.serialize_to_json(GAME),
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

# ---- Environment ----------------------------------------------------------

puts "Ruby:   #{RUBY_DESCRIPTION}"
puts "AR:     #{ActiveRecord::VERSION::STRING}"
puts "YJIT:   #{(defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?) ? "on" : "off"}"
unless defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
  warn "WARNING: YJIT is not enabled. Re-run with `--yjit` for production-target numbers."
end
puts

# ---- Benchmark ------------------------------------------------------------
# time: 5, warmup: 2 — same config as the upstream oj_serializers benchmark
# so absolute numbers stay comparable. GC is left enabled (default); see
# docs/research/game_serializer_results.md § GC.disable for why we don't
# disable it here.

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  # JSON-string-producing rows — apples-to-apples comparison.
  # `oj_serializers/json` uses `default_format :json` + `.one(GAME).to_s`
  # rather than `Oj.dump(.one_as_json(GAME))` so it doesn't pay the extra
  # Oj.dump dispatch the other JSON targets don't.
  x.report("oj_serializers/json") { GameOjJsonSerializer.one(GAME).to_s }
  x.report("panko") { GamePanko.new.serialize_to_json(GAME) }
  x.report("scg/json") { SCG_JSON.serialize_one(GAME) }
  x.report("scg/hash + Oj.dump") { Oj.dump SCG_HASH.serialize_one(GAME) }
  # Hash-producing rows — the in-process Hash output, no JSON encoding.
  x.report("oj_serializers/hash") { GameOjHashSerializer.one(GAME) }
  x.report("scg/hash") { SCG_HASH.serialize_one(GAME) }
  x.compare!
end
