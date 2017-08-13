# frozen_string_literal: true

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

  create_table :foo_holders, force: true do |t|
    t.string :name
    t.references :foo

    t.timestamps(null: false)
  end

  create_table :foos_holders, force: true do |t|
    t.string :name

    t.timestamps(null: false)
  end
end

class Foo < ActiveRecord::Base
end

class FoosHolder < ActiveRecord::Base
  has_many :foos
end

class FooHolder < ActiveRecord::Base
  has_one :foo
end
