# frozen_string_literal: true

require_relative "support/benchmark"

# Children reached through a plain method, not an association. The child
# serializer's `models` picks the path: none stays generic, one compiles
# specialized, two compile one specialized body per model.
#
# The lists are built once, so the rows measure serialization only. The
# "all fields" rows include a json column, which the specialized path emits
# differently; "id, body" are fields both models have.

related_posts = DATASETS[:posts].first(3).freeze
related_mixed = DATASETS[:posts].select { |post| post.comments.any? }.first(2)
  .flat_map { |post| [post, post.comments.first] }.freeze

Bench::Post.define_method(:related_posts) { related_posts }
Bench::Post.define_method(:related_items) { related_mixed }

POST_FIELDS = %i[id title body views published metadata].freeze
ITEM_FIELDS = %i[id body].freeze

class RelatedNoModelsSerializer < Panko::Serializer
  attributes(*POST_FIELDS)
end

class RelatedOneModelSerializer < Panko::Serializer
  models Bench::Post
  attributes(*POST_FIELDS)
end

class ItemNoModelsSerializer < Panko::Serializer
  attributes(*ITEM_FIELDS)
end

class ItemOneModelSerializer < Panko::Serializer
  models Bench::Post
  attributes(*ITEM_FIELDS)
end

class ItemTwoModelsSerializer < Panko::Serializer
  models Bench::Post, Bench::Comment
  attributes(*ITEM_FIELDS)
end

def parent_serializer(source, child)
  Class.new(Panko::Serializer) do
    attributes :id, :title
    has_many source, serializer: child
  end
end

RelatedNoModelsPostSerializer = parent_serializer(:related_posts, RelatedNoModelsSerializer)
RelatedOneModelPostSerializer = parent_serializer(:related_posts, RelatedOneModelSerializer)
ItemOneModelPostSerializer = parent_serializer(:related_posts, ItemOneModelSerializer)
ItemTwoModelsOnePostSerializer = parent_serializer(:related_posts, ItemTwoModelsSerializer)
ItemNoModelsMixedSerializer = parent_serializer(:related_items, ItemNoModelsSerializer)
ItemTwoModelsMixedSerializer = parent_serializer(:related_items, ItemTwoModelsSerializer)

def children_json(records, serializer)
  Panko::ArraySerializer.new(records, each_serializer: serializer).to_json
end

benchmark_scenario "ChildrenFromModels", type: :posts do |records|
  {
    "posts, all fields, no models" => -> { children_json(records, RelatedNoModelsPostSerializer) },
    "posts, all fields, one model" => -> { children_json(records, RelatedOneModelPostSerializer) },
    "posts, id+body, one model" => -> { children_json(records, ItemOneModelPostSerializer) },
    "posts, id+body, two models" => -> { children_json(records, ItemTwoModelsOnePostSerializer) },
    "posts+comments, id+body, no models" => -> { children_json(records, ItemNoModelsMixedSerializer) },
    "posts+comments, id+body, two models" => -> { children_json(records, ItemTwoModelsMixedSerializer) }
  }
end
