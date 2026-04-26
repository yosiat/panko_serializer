# frozen_string_literal: true

class Post < ActiveRecord::Base
  has_one :author
  has_many :comments
end

class Author < ActiveRecord::Base
  belongs_to :post, optional: true
end

class Comment < ActiveRecord::Base
  belongs_to :post, optional: true
end
