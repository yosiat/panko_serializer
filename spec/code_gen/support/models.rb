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
