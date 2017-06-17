module Panko
  class HasOneAttribute < RelationshipAttribute
    def create_serializer(options={})
      @serializer_const.new serializer_options(options)
    end
  end
end
