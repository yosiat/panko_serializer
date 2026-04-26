# frozen_string_literal: true

class Post < ActiveRecord::Base
  has_one :author
end

class Author < ActiveRecord::Base
  belongs_to :post, optional: true
end
