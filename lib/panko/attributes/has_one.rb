module Panko
  class HasOneAttribute < RelationshipAttribute
    def create_serializer(serializer_const, options={})
      serializer_const.new serializer_options(options)
    end
  end
end
