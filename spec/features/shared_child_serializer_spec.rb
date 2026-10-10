# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

describe "A child serializer used by several associations" do
  let(:game_name) { "final" }
  let(:first_player_name) { "Ann" }
  let(:second_player_name) { "Ben" }
  let(:game) do
    record = Game.create!(name: game_name)
    first = record.players.create!(name: first_player_name)
    record.players.create!(name: second_player_name)
    record.update!(best_player: first)
    Game.includes(:best_player, :players).find(record.id)
  end

  before do
    Temping.create(:game) do
      with_columns do |t|
        t.string :name
        t.bigint :best_player_id
      end
    end
    Temping.create(:player) do
      with_columns do |t|
        t.string :name
        t.bigint :game_id
      end
    end
    Game.has_many :players
    Game.belongs_to :best_player, class_name: "Player", optional: true
    Player.belongs_to :game, optional: true

    stub_const("SharedPlayerSerializer", Class.new(Panko::Serializer) do
      attributes :id, :name, :title

      def title
        "#{object.name}!"
      end
    end)
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @dump_dir = dir
      example.run
    end
  end

  def dumped_files(serializer_class)
    Panko::CodeGen.dump(serializer_class.descriptor, output: :json, path: File.join(@dump_dir, "root.rb"))
    Dir.children(@dump_dir).sort
  end

  def player_json(player, fields = [:id, :name, :title])
    values = {id: player.id, name: player.name, title: "#{player.name}!"}
    values.slice(*fields)
  end

  context "when both associations use the child unchanged" do
    let(:game_serializer) do
      stub_const("SharedGameSerializer", Class.new(Panko::Serializer) do
        attributes :name
        has_one :best_player, serializer: SharedPlayerSerializer
        has_many :players, serializer: SharedPlayerSerializer
      end)
    end

    it "generates one class for the child" do
      expect(dumped_files(game_serializer)).to eq(["root.rb", "shared_player_serializer_json.rb"])
    end

    it "serializes each association with its own records" do
      expected = Oj.dump({
        "name" => game_name,
        "best_player" => player_json(game.best_player).transform_keys(&:to_s),
        "players" => game.players.map { |player| player_json(player).transform_keys(&:to_s) }
      }, mode: :compat)

      expect(game_serializer.new.serialize_to_json(game)).to eq(expected)
    end
  end

  context "when one association narrows the child with only:" do
    let(:game_serializer) do
      stub_const("NarrowedGameSerializer", Class.new(Panko::Serializer) do
        attributes :name
        has_one :best_player, serializer: SharedPlayerSerializer, only: [:id]
        has_many :players, serializer: SharedPlayerSerializer
      end)
    end

    it "generates a class for each shape of the child" do
      expect(dumped_files(game_serializer))
        .to eq(["root.rb", "shared_player_serializer_2_json.rb", "shared_player_serializer_json.rb"])
    end

    it "keeps the narrowed shape on its own association" do
      output = game_serializer.new.serialize(game)

      expect(output["best_player"]).to eq(player_json(game.best_player, [:id]).transform_keys(&:to_s))
      expect(output["players"]).to eq(game.players.map { |player| player_json(player).transform_keys(&:to_s) })
    end
  end

  context "when a serializer references itself" do
    let(:node_serializer) do
      stub_const("SharedNodeSerializer", Class.new(Panko::Serializer) do
        attributes :name
      end).tap do |serializer|
        serializer.has_many :children, serializer: serializer
      end
    end

    it "generates a class for the parent and one for the one-level snapshot" do
      expect(dumped_files(node_serializer)).to eq(["root.rb", "shared_node_serializer_json.rb"])
    end
  end
end
