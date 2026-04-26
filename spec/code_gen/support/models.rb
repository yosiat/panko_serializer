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
end

class Vehicle < ActiveRecord::Base
end

class Car < Vehicle
  def make
    super.titleize
  end
end
