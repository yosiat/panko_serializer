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
    t.references :parent_comment, foreign_key: {to_table: :comments}
    t.string :body
  end

  create_table :vehicles, force: true do |t|
    t.string :type
    t.string :vin
    t.string :make
  end

  create_table :folders, force: true do |t|
    t.string :name
    t.references :parent_folder, foreign_key: {to_table: :folders}
  end

  create_table :items, force: true do |t|
    t.string :name
    t.references :folder, foreign_key: true
    t.references :subfolder, foreign_key: {to_table: :folders}
  end
end
