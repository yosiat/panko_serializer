module Panko
  class HasManyAttribute < RelationshipAttribute
    def create_serializer(serializer_const, options={})

      Panko::ArraySerializer.new([], serializer_options(options).merge(
        each_serializer: serializer_const
      ))
    end
  end
end
