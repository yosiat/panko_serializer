# frozen_string_literal: true

class Post < ActiveRecord::Base
  has_one :author
  has_many :comments

  def title
    super.upcase
  end

  def headline
    "#{title} (id=#{id})"
  end
end

# Bare AR model (no reader overrides) targeted by the S12.5 JSON-column
# emit fixtures and behavior specs. +Post+ above overrides +#title+, which
# breaks the byte-identical assertions for the +:html_safe+ snapshot —
# +PlainPost+ keeps every Attribute as raw column-backed access so the
# Specialized-path emit shape stays predictable.
class PlainPost < ActiveRecord::Base
  self.table_name = "posts"
end

class Author < ActiveRecord::Base
  belongs_to :post, optional: true
end

# Sibling AR model paired with +PlainPost+ in the non-uniform-Specialized
# JSON-column regression fixture (#61). Its +metadata+ column is +t.string+,
# so +ActiveRecord::AccessClassifier.json_typed?+ returns +false+ for it —
# the +ar_classes.all?+ guard in
# +Generators::RecordAccess::Specialized.json_column_attribute?+ then
# rejects the whole +Models+ set and the per-Attribute emit downgrades to
# today's +push_value+ shape.
class PlainNote < ActiveRecord::Base
  self.table_name = "notes"
end

class Comment < ActiveRecord::Base
  belongs_to :post, optional: true
  belongs_to :parent_comment, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_comment_id
end

class Vehicle < ActiveRecord::Base
end

class Car < Vehicle
  def make
    super.titleize
  end
end

class Folder < ActiveRecord::Base
  has_many :items
end

class Item < ActiveRecord::Base
  belongs_to :folder, optional: true
  belongs_to :subfolder, class_name: "Folder", optional: true
end
