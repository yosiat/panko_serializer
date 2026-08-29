# frozen_string_literal: true

require_relative "support/benchmark"

# Cross-library serializer benchmark: Panko vs its competitors, serializing a
# nested object graph (Game -> scores, best_player, players[]) to JSON. Two
# workloads per library — a single record and a collection — measured side by
# side under YJIT.
#
# Every competitor row is gated on producing output BYTE-IDENTICAL to Panko's:
# a library whose bytes diverge (different key order, spacing, escaping) is
# skipped with a warning rather than compared, so the numbers stay honest and
# apples-to-apples.
#
# Adapted from oj_serializers' game_serializer_benchmark.rb
# (https://github.com/ElMassimo/oj_serializers/blob/master/benchmarks/game_serializer_benchmark.rb),
# MIT-licensed, Copyright (c) 2020 Maximo Mussini. Owns its own Game/Player
# schema — including the upstream `scores` alias that walks back to the game
# itself — so absolute numbers stay comparable to oj_serializers' published run.
#
# Run (YJIT — the production target):
#   BUNDLE_GEMFILE=gemfiles/8.0.0.gemfile bundle exec ruby --yjit benchmarks/game_serializer.rb
#
# Collection size defaults to 100 games; override with COUNT=<n>. TARGET=<substr>
# filters rows (e.g. TARGET=single, TARGET=alba).

# Competitors are optional: the bench runs with whichever gems are installed,
# so a missing one degrades to a skipped row instead of a load error.
def try_require(lib)
  require lib
  true
rescue LoadError
  warn "#{lib} not installed — its benchmark row will be skipped"
  false
end

HAVE_ALBA = try_require("alba")
HAVE_BLUEPRINTER = try_require("blueprinter")

# --- Schema + models ------------------------------------------------------

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

  # Mirrors `Game.prepend Module.new { def scores; self; end }` from the source
  # benchmark — has_one :scores walks back to the game itself so the Scores
  # serializer reads high_score/score off the game's own row.
  def scores
    self
  end
end

Game.define_attribute_methods
Player.define_attribute_methods

# --- Seed data: one game for the single row, a collection for the many row --

COLLECTION_SIZE = (ENV["COUNT"] && !ENV["COUNT"].empty?) ? ENV["COUNT"].to_i : 100

Game.insert_all(
  COLLECTION_SIZE.times.map do |i|
    {name: "Game ##{i}", high_score: 1500 + i, score: 3000 + i}
  end
)
Player.insert_all(
  Game.order(:id).pluck(:id).flat_map do |game_id|
    [
      {first_name: "Alexey", last_name: "Pajitnov", game_id: game_id},
      {first_name: "Vadim", last_name: "Gerasimov", game_id: game_id}
    ]
  end
)
# Each game's best player is its first player — one correlated UPDATE.
Game.connection.execute(<<~SQL)
  UPDATE games SET best_player_id =
    (SELECT MIN(id) FROM players WHERE players.game_id = games.id)
SQL

GAMES = Game.includes(:best_player, :players).order(:id).to_a
GAME = GAMES.first

# --- Panko (the subject) --------------------------------------------------

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

# --- oj_serializers -------------------------------------------------------
# `default_format :json` makes `.one` / `.many` return an Oj::StringWriter whose
# `.to_s` materializes JSON in one dispatch — the apples-to-apples shape against
# Panko's serialize_to_json. See https://github.com/ElMassimo/oj_serializers.

class PlayerOj < OjSerializers::Serializer
  default_format :json
  attributes :id, :first_name, :last_name

  attribute
  def full_name
    @object.full_name
  end
end

class ScoresOj < OjSerializers::Serializer
  default_format :json
  attributes :high_score, :score
end

class GameOj < OjSerializers::Serializer
  default_format :json
  attributes :id, :name
  has_one :scores, serializer: ScoresOj
  has_one :best_player, serializer: PlayerOj
  has_many :players, serializer: PlayerOj
end

# --- alba -----------------------------------------------------------------

if HAVE_ALBA
  Alba.backend = :oj

  class PlayerAlba
    include Alba::Resource

    attributes :id, :first_name, :last_name
    attribute :full_name do |player|
      player.full_name
    end
  end

  class ScoresAlba
    include Alba::Resource

    attributes :high_score, :score
  end

  class GameAlba
    include Alba::Resource

    attributes :id, :name
    one :scores, resource: ScoresAlba
    one :best_player, resource: PlayerAlba
    many :players, resource: PlayerAlba
  end
end

# --- blueprinter ----------------------------------------------------------
# Blueprinter's default sorts fields alphabetically; :definition keeps
# declaration order so the bytes line up with Panko. Plain `field :id` (not
# `identifier`) avoids the always-first id reordering.

if HAVE_BLUEPRINTER
  Blueprinter.configure { |config| config.sort_fields_by = :definition }

  class PlayerBlueprint < Blueprinter::Base
    field :id
    field :first_name
    field :last_name
    field(:full_name) { |player| player.full_name }
  end

  class ScoresBlueprint < Blueprinter::Base
    field :high_score
    field :score
  end

  class GameBlueprint < Blueprinter::Base
    field :id
    field :name
    association :scores, blueprint: ScoresBlueprint
    association :best_player, blueprint: PlayerBlueprint
    association :players, blueprint: PlayerBlueprint
  end
end

# --- plain baselines (ceiling + floor) ------------------------------------
# Hand-built Hash so key order and shape are exactly Panko's; Oj.dump is the
# "speed of light" ceiling, JSON.generate the stdlib floor.

def player_hash(player)
  {
    id: player.id,
    first_name: player.first_name,
    last_name: player.last_name,
    full_name: player.full_name
  }
end

def game_hash(game)
  {
    id: game.id,
    name: game.name,
    scores: {high_score: game.high_score, score: game.score},
    best_player: player_hash(game.best_player),
    players: game.players.map { |player| player_hash(player) }
  }
end

# --- Byte-identical parity gate -------------------------------------------
# Panko is the reference. A candidate whose output is not byte-for-byte equal is
# dropped from the run (with a warning) so only comparable rows are timed. The
# one tolerated difference is a trailing newline: oj_serializers' Oj::StringWriter
# appends one, which is a transport artifact rather than a content difference, so
# the gate compares modulo String#chomp. The timed lambdas are left untouched, so
# each row still measures its library's natural output.

def gated_rows(kind, panko_lambda, candidates)
  reference = panko_lambda.call
  rows = {"panko" => panko_lambda}
  candidates.each do |label, callable|
    output = callable.call
    if output.chomp == reference.chomp
      rows[label] = callable
    else
      warn "SKIP #{kind}/#{label}: output not byte-identical to panko"
      warn "  panko: #{reference[0, 160]}"
      warn "  #{label}: #{output.to_s[0, 160]}"
    end
  end
  rows
end

single_panko = -> { GamePanko.new.serialize_to_json(GAME) }
collection_panko = -> { Panko::ArraySerializer.new(GAMES, each_serializer: GamePanko).to_json }

single_candidates = {
  "oj_serializers" => -> { GameOj.one(GAME).to_s },
  "oj" => -> { Oj.dump(game_hash(GAME), mode: :strict) },
  "rails" => -> { JSON.generate(game_hash(GAME)) }
}
collection_candidates = {
  "oj_serializers" => -> { GameOj.many(GAMES).to_s },
  "oj" => -> { Oj.dump(GAMES.map { |game| game_hash(game) }, mode: :strict) },
  "rails" => -> { JSON.generate(GAMES.map { |game| game_hash(game) }) }
}
if HAVE_ALBA
  single_candidates["alba"] = -> { GameAlba.new(GAME).serialize }
  collection_candidates["alba"] = -> { GameAlba.new(GAMES).serialize }
end
if HAVE_BLUEPRINTER
  single_candidates["blueprinter"] = -> { GameBlueprint.render(GAME) }
  collection_candidates["blueprinter"] = -> { GameBlueprint.render(GAMES) }
end

single_rows = gated_rows("single", single_panko, single_candidates)
collection_rows = gated_rows("collection", collection_panko, collection_candidates)

puts "Byte-identical vs panko:"
puts "  single (1 game):          #{single_rows.keys.join(", ")}"
puts "  collection (#{COLLECTION_SIZE} games):  #{collection_rows.keys.join(", ")}"
puts "Sample (single): #{single_panko.call}"
puts

# --- Scenario rows --------------------------------------------------------

rows = {}
single_rows.each { |label, callable| rows["single/#{label}"] = callable }
collection_rows.each { |label, callable| rows["collection/#{label}"] = callable }

rows.each do |row_label, row_callable|
  next if BENCHMARK_CONFIG.target && !row_label.downcase.include?(BENCHMARK_CONFIG.target.downcase)
  benchmark("GameSerializer/#{row_label}", &row_callable)
end
