# frozen_string_literal: true

require "spec_helper"
require "active_record/connection_adapters/postgresql_adapter"

describe "Filtering Serialization" do
  class FooSerializer < Panko::Serializer
    attributes :name, :address
  end

  context "basic filtering" do
    it "supports only filter" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(-> { FooSerializer.new(only: [:name]) }, "name" => foo.name)
    end

    it "supports except filter" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(-> { FooSerializer.new(except: [:name]) }, "address" => foo.address)
    end
  end

  context "association filtering" do
    it "filters associations" do
      class FoosHolderForFilterTestSerializer < Panko::Serializer
        attributes :name

        has_many :foos, serializer: FooSerializer
      end

      serializer_factory = -> { FoosHolderForFilterTestSerializer.new(only: [:foos]) }

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

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

    it 'supports nested "only" filter' do
      class FoosHolderSerializer < Panko::Serializer
        attributes :name
        has_many :foos, serializer: FooSerializer
      end

      serializer_factory = -> { FoosHolderSerializer.new(only: {foos: [:address]}) }

      foo1 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foo2 = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload
      foos_holder = FoosHolder.create(name: Faker::Lorem.word, foos: [foo1, foo2]).reload

      expect(foos_holder).to serialized_as(serializer_factory, "name" => foos_holder.name,
        "foos" => [
          {
            "address" => foo1.address
          },
          {
            "address" => foo2.address
          }
        ])
    end
  end

  context "complex nested filters" do
    class UserSerializer < Panko::Serializer
      attributes :name, :email
    end

    class TeamSerializer < Panko::Serializer
      attributes :name
      has_many :users, serializer: UserSerializer
    end

    class OrganizationSerializer < Panko::Serializer
      attributes :name
      has_many :teams, serializer: TeamSerializer
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
    it "filters based on aliased attribute name" do
      class FooWithAliasFilterSerializer < Panko::Serializer
        attributes :address

        aliases name: :full_name
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      # Filter using the alias name
      expect(foo).to serialized_as(-> { FooWithAliasFilterSerializer.new(only: [:full_name]) },
        "full_name" => foo.name)

      # Filter using the original name should also work
      expect(foo).to serialized_as(-> { FooWithAliasFilterSerializer.new(except: [:address]) },
        "full_name" => foo.name)
    end
  end

  context "filter interactions" do
    it "tests interaction between ArraySerializer filters and has_many association filters" do
      class TeamArrayFilterSerializer < Panko::Serializer
        attributes :name
        has_many :users, serializer: "UserSerializer", only: [:name]
      end

      team = Team.create(name: Faker::Team.name)
      user1 = User.create(name: Faker::Name.name, email: Faker::Internet.email, team: team)
      user2 = User.create(name: Faker::Name.name, email: Faker::Internet.email, team: team)

      # ArraySerializer with only filter AND has_many with only filter
      array_serializer_factory = -> {
        Panko::ArraySerializer.new([],
          each_serializer: TeamArrayFilterSerializer,
          only: [:users])
      }

      expect([team]).to serialized_as(array_serializer_factory, [
        {
          "users" => [
            {"name" => user1.name},
            {"name" => user2.name}
          ]
        }
      ])
    end
  end

  context "nested except filters" do
    it "supports nested except filters" do
      class TeamWithExceptSerializer < Panko::Serializer
        attributes :name
        has_many :users, serializer: "UserSerializer"
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

    it "supports deeply nested except filters" do
      org = Organization.create(name: Faker::Company.name)
      team = Team.create(name: Faker::Team.name, organization: org)
      user = User.create(name: Faker::Name.name, email: Faker::Internet.email, team: team)

      serializer_factory = -> { OrganizationSerializer.new(except: {teams: {users: [:email]}}) }

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
  end

  context "only vs except precedence" do
    it "only takes precedence over except when both are provided" do
      class FooWithBothFiltersSerializer < Panko::Serializer
        attributes :name, :address

        def self.filters_for(_context, _scope)
          {
            only: [:name],
            except: [:address]  # This should be ignored since only is present
          }
        end
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(FooWithBothFiltersSerializer, "name" => foo.name)
    end

    it "only takes precedence in constructor options" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      # When both only and except are provided, only should take precedence
      serializer_factory = -> { FooSerializer.new(only: [:name], except: [:address]) }

      expect(foo).to serialized_as(serializer_factory, "name" => foo.name)
    end
  end

  context "filters_for interaction" do
    it "combines filters_for with constructor only/except options" do
      class FooWithFiltersForInteractionSerializer < Panko::Serializer
        attributes :name, :address

        def self.filters_for(_context, _scope)
          {
            except: [:address]
          }
        end
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      # Constructor options should be merged with filters_for
      serializer_factory = -> { FooWithFiltersForInteractionSerializer.new(only: [:name]) }

      expect(foo).to serialized_as(serializer_factory, "name" => foo.name)
    end

    it "passes context and scope to filters_for method" do
      class FooWithContextFiltersSerializer < Panko::Serializer
        attributes :name, :address

        def self.filters_for(context, scope)
          if context && context[:admin]
            {only: [:name, :address]}
          else
            {only: [:name]}
          end
        end
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      # Admin context should show both fields
      admin_serializer = -> { FooWithContextFiltersSerializer.new(context: {admin: true}) }
      expect(foo).to serialized_as(admin_serializer,
        "name" => foo.name,
        "address" => foo.address)

      # Non-admin context should show only name
      user_serializer = -> { FooWithContextFiltersSerializer.new(context: {admin: false}) }
      expect(foo).to serialized_as(user_serializer, "name" => foo.name)
    end
  end

  context "deeply nested filters" do
    it "filters on 2+ levels deep associations" do
      org = Organization.create(name: Faker::Company.name)
      team = Team.create(name: Faker::Team.name, organization: org)
      user = User.create(name: Faker::Name.name, email: Faker::Internet.email, team: team)

      # Filter only email from deeply nested users
      serializer_factory = -> {
        OrganizationSerializer.new(only: {
          teams: {
            users: [:email]
          }
        })
      }

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

    it "supports mixed only and except at different nesting levels" do
      org = Organization.create(name: Faker::Company.name)
      team = Team.create(name: Faker::Team.name, organization: org)
      user = User.create(name: Faker::Name.name, email: Faker::Internet.email, team: team)

      # Only teams, but except email from users
      serializer_factory = -> {
        OrganizationSerializer.new(only: [:teams], except: {
          teams: {
            users: [:email]
          }
        })
      }

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
    it "raises error for non-Array/Hash only filters" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      # Test with invalid filter types - currently raises NoMethodError
      expect do
        FooSerializer.new(only: "invalid").serialize(foo)
      end.to raise_error(NoMethodError)
      # TODO: change the error to be ArgumentError
    end

    it "raises error for non-Array/Hash except filters" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect do
        FooSerializer.new(except: 123).serialize(foo)
      end.to raise_error(NoMethodError)
      # TODO: change the error to be ArgumentError
    end

    it "handles filters on non-existent attributes" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      # Filter should ignore non-existent attributes
      serializer_factory = -> { FooSerializer.new(only: [:name, :non_existent_field]) }

      expect(foo).to serialized_as(serializer_factory, "name" => foo.name)
    end

    it "handles filters on non-existent associations" do
      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      # Filter should ignore non-existent associations
      serializer_factory = -> { FooSerializer.new(only: {non_existent_association: [:name]}) }

      expect(foo).to serialized_as(serializer_factory,
        "name" => foo.name,
        "address" => foo.address)
    end
  end

  context "filters_for method" do
    it "fetches the filters from the serializer" do
      class FooWithFiltersForSerializer < Panko::Serializer
        attributes :name, :address

        def self.filters_for(_context, _scope)
          {
            only: [:name]
          }
        end
      end

      foo = Foo.create(name: Faker::Lorem.word, address: Faker::Lorem.word).reload

      expect(foo).to serialized_as(FooWithFiltersForSerializer, "name" => foo.name)
    end
  end
end
