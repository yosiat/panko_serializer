# frozen_string_literal: true
###########################################
# Setup active record models
##########################################
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
      body: "something about how password restrictions are evil, and less secure, and with the math to prove it.",
      title: "Your bank is does not know how to do security",
      author: Author.create(name: "Preston Sego"),
      data: { a: 1, b: 2, c: 3 }
    )
  end
end
