# frozen_string_literal: true

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
  has_many :posts
end

class Post < ActiveRecord::Base
  belongs_to :author
end

class PostWithAliasModel < ActiveRecord::Base
  self.table_name = "posts"

  alias_attribute :new_id, :id
  alias_attribute :new_body, :body
  alias_attribute :new_title, :title
  alias_attribute :new_author_id, :author_id
  alias_attribute :new_created_at, :created_at
end

Post.transaction do
  2300.times do
    Post.create(
      body: SecureRandom.hex(30),
      title: SecureRandom.hex(20),
      author: Author.create(name: SecureRandom.alphanumeric),
      data: {a: 1, b: 2, c: 3}
    )
  end
end
