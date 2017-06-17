
module Panko
  class HasOneAttribute < RelationshipAttribute
    def create_serializer(options={})
      Panko::CACHE.fetch(@serializer_const, serializer_options(options))
    end
  end
end
