# frozen_string_literal: true

require "spec_helper"

describe "Filtering Serialization" do
  context "basic filtering" do
    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
        end
      end
    end

    let(:foo_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name, :address
      end
    end

    before { stub_const("FooSerializer", foo_serializer_class) }

    it "supports only filter" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      expect(foo).to serialized_as(-> { FooSerializer.new(only: [:name]) }, "name" => foo.name)
    end

    it "supports except filter" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      expect(foo).to serialized_as(-> { FooSerializer.new(except: [:name]) }, "address" => foo.address)
    end
  end

  context "association filtering" do
    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
          t.references :foos_holder
        end

        belongs_to :foos_holder, optional: true
      end

      Temping.create(:foos_holder) do
        with_columns do |t|
          t.string :name
        end

        has_many :foos
      end
    end

    let(:foo_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name, :address
      end
    end

    before { stub_const("FooSerializer", foo_serializer_class) }

    it "filters associations" do
      class FoosHolderForFilterTestSerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer
      end

      serializer_factory = -> { FoosHolderForFilterTestSerializer.new(only: [:foos]) }

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2])

      expect(foos_holder).to serialized_as(serializer_factory, "foos" => [
        {
          "name" => foo1.name,
          "address" => foo1.address
        },
        {
          "name" => foo2.name,
          "address" => foo2.address
        }
      ])
    end

    it "filters association attributes" do
      class FoosHolderForFilterTestSerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer
      end

      serializer_factory = -> { FoosHolderForFilterTestSerializer.new(only: {foos: [:name]}) }

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2])

      expect(foos_holder).to serialized_as(serializer_factory, "name" => foos_holder.name,
        "foos" => [
          {
            "name" => foo1.name
          },
          {
            "name" => foo2.name
          }
        ])
    end
  end

  context "complex nested filters" do
    before do
      Temping.create(:user) do
        with_columns do |t|
          t.string :name
          t.string :email
          t.references :team
        end

        belongs_to :team
      end

      Temping.create(:team) do
        with_columns do |t|
          t.string :name
          t.references :organization
        end

        belongs_to :organization
        has_many :users
      end

      Temping.create(:organization) do
        with_columns do |t|
          t.string :name
        end

        has_many :teams
        has_many :users, through: :teams
      end
    end

    let(:user_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name, :email
      end
    end

    let(:team_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name
        has_many :users, serializer: "UserSerializer"
      end
    end

    let(:organization_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name
        has_many :teams, serializer: "TeamSerializer"
      end
    end

    before do
      stub_const("UserSerializer", user_serializer_class)
      stub_const("TeamSerializer", team_serializer_class)
      stub_const("OrganizationSerializer", organization_serializer_class)
    end

    it "supports complex nested only clauses on has_many" do
      org = Organization.create(name: Faker::Company.name)
      team = Team.create(name: Faker::Team.name, organization: org)
      user = User.create(name: Faker::Name.name, email: Faker::Internet.email, team: team)

      serializer_factory = -> { OrganizationSerializer.new(only: {teams: {users: [:email]}}) }

      expect(org).to serialized_as(serializer_factory,
        "name" => org.name,
        "teams" => [
          {
            "name" => team.name,
            "users" => [
              {"email" => user.email}
            ]
          }
        ])
    end

    it "supports complex nested only clauses on has_one" do
      class TeamWithOrgSerializer < Panko::Serializer
        attributes :name
        has_one :organization, serializer: OrganizationSerializer
      end

      org = Organization.create(name: Faker::Company.name)
      team = Team.create(name: Faker::Team.name, organization: org)

      serializer_factory = -> { TeamWithOrgSerializer.new(only: {organization: [:name]}) }

      expect(team).to serialized_as(serializer_factory,
        "name" => team.name,
        "organization" => {
          "name" => org.name
        })
    end
  end

  context "aliased attribute filtering" do
    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
        end
      end
    end

    it "filters based on aliased attribute name" do
      class FooWithAliasFilterSerializer < Panko::Serializer
        attributes :address

        aliases name: :full_name
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      # Filter using the alias name
      expect(foo).to serialized_as(-> { FooWithAliasFilterSerializer.new(only: [:full_name]) },
        "full_name" => foo.name)

      # Filter using except should also work
      expect(foo).to serialized_as(-> { FooWithAliasFilterSerializer.new(except: [:address]) },
        "full_name" => foo.name)
    end
  end

  context "filter interactions" do
    before do
      Temping.create(:user) do
        with_columns do |t|
          t.string :name
          t.string :email
          t.references :team
        end

        belongs_to :team
      end

      Temping.create(:team) do
        with_columns do |t|
          t.string :name
        end

        has_many :users
      end
    end

    let(:user_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name, :email
      end
    end

    before { stub_const("UserSerializer", user_serializer_class) }

    it "tests interaction between ArraySerializer filters and has_many association filters" do
      class TeamArrayFilterSerializer < Panko::Serializer
        attributes :name
        has_many :users, serializer: UserSerializer
      end

      team = Team.create(name: Faker::Team.name)
      user1 = User.create(name: Faker::Name.name, email: Faker::Internet.email, team: team)
      user2 = User.create(name: Faker::Name.name, email: Faker::Internet.email, team: team)

      # ArraySerializer filter should work with association filters
      array_serializer = Panko::ArraySerializer.new([team], each_serializer: TeamArrayFilterSerializer, only: {users: [:name]})
      result = array_serializer.to_json

      expected = [
        {
          "name" => team.name,
          "users" => [
            {"name" => user1.name},
            {"name" => user2.name}
          ]
        }
      ]

      expect(JSON.parse(result)).to eq(expected)
    end
  end

  context "nested except filters" do
    before do
      Temping.create(:user) do
        with_columns do |t|
          t.string :name
          t.string :email
          t.references :team
        end

        belongs_to :team
      end

      Temping.create(:team) do
        with_columns do |t|
          t.string :name
        end

        has_many :users
      end
    end

    let(:user_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name, :email
      end
    end

    before { stub_const("UserSerializer", user_serializer_class) }

    it "supports nested except filters" do
      class TeamWithExceptSerializer < Panko::Serializer
        attributes :name
        has_many :users, serializer: UserSerializer
      end

      team = Team.create(name: Faker::Team.name)
      user = User.create(name: Faker::Name.name, email: Faker::Internet.email, team: team)

      serializer_factory = -> { TeamWithExceptSerializer.new(except: {users: [:email]}) }

      expect(team).to serialized_as(serializer_factory,
        "name" => team.name,
        "users" => [
          {"name" => user.name}
        ])
    end
  end

  context "only vs except precedence" do
    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
        end
      end
    end

    let(:foo_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name, :address
      end
    end

    before { stub_const("FooSerializer", foo_serializer_class) }

    it "only takes precedence over except when both are provided" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      expect(foo).to serialized_as(-> { FooSerializer.new(only: [:name], except: [:address]) }, "name" => foo.name)
    end
  end

  context "filters_for interaction" do
    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
        end
      end
    end

    it "combines filters_for with constructor only/except options" do
      class FooWithFiltersForSerializer < Panko::Serializer
        attributes :name, :address

        def self.filters_for(context, scope)
          {except: [:address]}
        end
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      # filters_for except should be combined with constructor only
      expect(foo).to serialized_as(-> { FooWithFiltersForSerializer.new(only: [:name]) }, "name" => foo.name)
    end

    it "passes context and scope to filters_for method" do
      class FooWithContextFiltersSerializer < Panko::Serializer
        attributes :name, :address

        def self.filters_for(context, scope)
          if context[:user_role] == "admin"
            {only: [:name, :address]}
          else
            {only: [:name]}
          end
        end
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      # Test with admin context
      expect(foo).to serialized_as(-> { FooWithContextFiltersSerializer.new(context: {user_role: "admin"}) },
        "name" => foo.name, "address" => foo.address)

      # Test with regular user context
      expect(foo).to serialized_as(-> { FooWithContextFiltersSerializer.new(context: {user_role: "user"}) },
        "name" => foo.name)
    end
  end

  context "deeply nested filters" do
    before do
      Temping.create(:user) do
        with_columns do |t|
          t.string :name
          t.string :email
          t.references :team
        end

        belongs_to :team
      end

      Temping.create(:team) do
        with_columns do |t|
          t.string :name
          t.references :organization
        end

        belongs_to :organization
        has_many :users
      end

      Temping.create(:organization) do
        with_columns do |t|
          t.string :name
        end

        has_many :teams
        has_many :users, through: :teams
      end
    end

    let(:user_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name, :email
      end
    end

    let(:team_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name
        has_many :users, serializer: "UserSerializer"
      end
    end

    let(:organization_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name
        has_many :teams, serializer: "TeamSerializer"
      end
    end

    before do
      stub_const("UserSerializer", user_serializer_class)
      stub_const("TeamSerializer", team_serializer_class)
      stub_const("OrganizationSerializer", organization_serializer_class)
    end

    it "filters on 2+ levels deep associations" do
      org = Organization.create(name: Faker::Company.name)
      team = Team.create(name: Faker::Team.name, organization: org)
      user = User.create(name: Faker::Name.name, email: Faker::Internet.email, team: team)

      serializer_factory = -> { OrganizationSerializer.new(only: {teams: {users: [:name]}}) }

      expect(org).to serialized_as(serializer_factory,
        "name" => org.name,
        "teams" => [
          {
            "name" => team.name,
            "users" => [
              {"name" => user.name}
            ]
          }
        ])
    end

    it "supports mixed only and except at different nesting levels" do
      org = Organization.create(name: Faker::Company.name)
      team = Team.create(name: Faker::Team.name, organization: org)
      user = User.create(name: Faker::Name.name, email: Faker::Internet.email, team: team)

      # Use only at top level, except at nested level
      serializer_factory = -> { OrganizationSerializer.new(only: [:teams], except: {teams: {users: [:email]}}) }

      expect(org).to serialized_as(serializer_factory,
        "teams" => [
          {
            "name" => team.name,
            "users" => [
              {"name" => user.name}
            ]
          }
        ])
    end
  end

  context "invalid filter values" do
    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
        end
      end
    end

    let(:foo_serializer_class) do
      Class.new(Panko::Serializer) do
        attributes :name, :address
      end
    end

    before { stub_const("FooSerializer", foo_serializer_class) }

    it "raises error for non-Array/Hash only filters" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      expect do
        FooSerializer.new(only: "invalid").serialize(foo)
      end.to raise_error(NoMethodError)
      # TODO: change the error to be ArgumentError
    end

    it "raises error for non-Array/Hash except filters" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)
      expect do
        FooSerializer.new(except: 123).serialize(foo)
      end.to raise_error(NoMethodError)
      # TODO: change the error to be ArgumentError
    end

    it "handles filters on non-existent attributes" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      # Should not raise error, just ignore non-existent attributes
      expect(foo).to serialized_as(-> { FooSerializer.new(only: [:name, :non_existent]) }, "name" => foo.name)
    end

    it "handles filters on non-existent associations" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      serializer_factory = -> { FooSerializer.new(only: {non_existent_association: [:name]}) }

      expect(foo).to serialized_as(serializer_factory,
        "name" => foo.name,
        "address" => foo.address)
    end
  end

  context "filters_for method" do
    before do
      Temping.create(:foo) do
        with_columns do |t|
          t.string :name
          t.string :address
        end
      end
    end

    it "fetches the filters from the serializer" do
      class FooWithFiltersForSerializer < Panko::Serializer
        attributes :name, :address

        def self.filters_for(context, scope)
          {only: [:name]}
        end
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word)

      expect(foo).to serialized_as(-> { FooWithFiltersForSerializer.new }, "name" => foo.name)
    end
  end
end
