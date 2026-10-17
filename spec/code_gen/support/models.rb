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

# +Post+ overrides +#title+; this model keeps every attribute a plain column read, so the
# Specialized emit and the byte-identical snapshots stay predictable.
class PlainPost < ActiveRecord::Base
  self.table_name = "posts"
end

class Author < ActiveRecord::Base
  belongs_to :post, optional: true
end

# Same +metadata+ name as +PlainPost+, but a +t.string+ column, so it is not JSON-typed.
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
