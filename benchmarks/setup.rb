# frozen_string_literal: true

###########################################
# Setup active record models
##########################################
require "active_record"
require "sqlite3"
require "securerandom"

# Change the following to reflect your database settings
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

# Don't show migration output when constructing fake db
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :authors, force: true do |t|
    t.string :name
    t.timestamps(null: false)
  end

  create_table :posts, force: true do |t|
    t.text :body
    t.string :title
    t.references :author
    t.json :data
    t.timestamps(null: false)
  end
end

class Author < ActiveRecord::Base
  has_one :profile
  has_many :posts
end

class Post < ActiveRecord::Base
  belongs_to :author
end

Post.destroy_all
Author.destroy_all

# Build out the data to serialize
Post.transaction do
  ENV.fetch("ITEMS_COUNT", "2300").to_i.times do
    Post.create(
      body: SecureRandom.hex(30),
      title: SecureRandom.hex(20),
      author: Author.create(name: SecureRandom.alphanumeric),
      data: {a: 1, b: 2, c: 3}
    )
  end
end
