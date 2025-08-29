# frozen_string_literal: true

require "logger"
require "active_record"
require "sqlite3"

# Change the following to reflect your database settings
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

# Don't show migration output when constructing fake db
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :foos, force: true do |t|
    t.string :name
    t.string :address

    t.references :foos_holder
    t.references :foo_holder

    t.timestamps(null: false)
  end

  create_table :goos, force: true do |t|
    t.string :name
    t.string :address

    t.references :foos_holder
    t.references :foo_holder

    t.timestamps(null: false)
  end

  create_table :foo_holders, force: true do |t|
    t.string :name
    t.references :foo

    t.timestamps(null: false)
  end

  create_table :foos_holders, force: true do |t|
    t.string :name

    t.timestamps(null: false)
  end

  # Tables for polymorphic associations
  create_table :comments, force: true do |t|
    t.string :content
    t.references :commentable, polymorphic: true

    t.timestamps(null: false)
  end

  create_table :posts, force: true do |t|
    t.string :title
    t.string :content

    t.timestamps(null: false)
  end

  create_table :articles, force: true do |t|
    t.string :title
    t.string :body

    t.timestamps(null: false)
  end

  # Tables for deeply nested associations
  create_table :organizations, force: true do |t|
    t.string :name

    t.timestamps(null: false)
  end

  create_table :teams, force: true do |t|
    t.string :name
    t.references :organization

    t.timestamps(null: false)
  end

  create_table :users, force: true do |t|
    t.string :name
    t.string :email
    t.references :team

    t.timestamps(null: false)
  end
end

class Foo < ActiveRecord::Base
end

class Goo < ActiveRecord::Base
end

class FoosHolder < ActiveRecord::Base
  has_many :foos
  has_many :goos
end

class FooHolder < ActiveRecord::Base
  has_one :foo
  has_one :goo
end

# Models for polymorphic associations
class Comment < ActiveRecord::Base
  belongs_to :commentable, polymorphic: true
end

class Post < ActiveRecord::Base
  has_many :comments, as: :commentable
end

class Article < ActiveRecord::Base
  has_many :comments, as: :commentable
end

# Models for deeply nested associations
class Organization < ActiveRecord::Base
  has_many :teams
  has_many :users, through: :teams
end

class Team < ActiveRecord::Base
  belongs_to :organization
  has_many :users
end

class User < ActiveRecord::Base
  belongs_to :team
  has_one :organization, through: :team
end
