# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :posts, force: true do |t|
    t.string :title
    t.string :body
    t.integer :views
  end

  create_table :authors, force: true do |t|
    t.references :post, foreign_key: true
    t.string :name
  end

  create_table :comments, force: true do |t|
    t.references :post, foreign_key: true
    t.string :body
  end
end
