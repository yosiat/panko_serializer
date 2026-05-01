# frozen_string_literal: true

ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :posts, force: true do |t|
    t.string :title
    t.string :body
    t.integer :views
    # Backs the S12.5 JSON-column emit path. Specs covering the JSON-typed
    # detection predicate and the +emit_json_column+ field emitter assert
    # against a real AR column whose +type_for_attribute+ resolves to
    # +ActiveRecord::Type::Json+ on every supported adapter.
    t.json :metadata
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
