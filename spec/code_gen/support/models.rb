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

class Author < ActiveRecord::Base
  belongs_to :post, optional: true
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
