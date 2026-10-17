# frozen_string_literal: true

require "spec_helper"

describe "Children reached through a plain method, specialized from the child serializer's models" do
  let(:stored) { '{"b": 1.50, "a": "<x>", "b": 2}' }
  let(:other_stored) { '{"z": 1.0, "z": [1.50]}' }
  let(:reencoded) { Oj.dump(Oj.load(stored), mode: :rails) }

  before do
    Temping.create(:post) do
      with_columns do |t|
        t.string :title
      end
    end
    Temping.create(:comment) do
      with_columns do |t|
        t.bigint :post_id
        t.string :type
        t.boolean :hidden, default: false
        t.json :meta
      end
    end
    Temping.create(:note) do
      with_columns do |t|
        t.bigint :post_id
        t.json :meta
      end
    end
    Post.has_many :comments
    Post.has_many :notes
    Comment.belongs_to :post, optional: true
    Note.belongs_to :post, optional: true
    Post.class_eval do
      define_method(:visible_comments) { comments.reject(&:hidden) }
      define_method(:first_comment) { comments.first }
      define_method(:attachments) { comments.to_a + notes.to_a }
    end
    stub_const("FlaggedComment", Class.new(Comment))
  end

  around do |example|
    original_enabled = Panko::Config.auto_specialization.enabled
    example.run
  ensure
    Panko::Config.auto_specialization.enabled = original_enabled
  end

  def define_serializer(name, parent = Panko::Serializer, &block)
    stub_const(name, Class.new(parent, &block))
  end

  def store_meta(record, text)
    record.class.where(id: record.id).update_all(["meta = ?", text])
  end

  def meta_texts(json, key)
    Array(Oj.load(json)[key]).map { |item| item["meta"] }
  end

  def comment_with(text, post, model: Comment)
    model.create!(post: post).tap { |record| store_meta(record, text) }
  end

  let(:post) { Post.create!(title: "Hello") }

  context "when the child serializer declares one model" do
    let!(:comment_serializer) do
      define_serializer("ModelsCommentSerializer") do
        models Comment
        attributes :id, :meta
      end
    end

    let!(:post_serializer) do
      define_serializer("ModelsPostSerializer") do
        attributes :title
        has_many :visible_comments, name: :comments, serializer: ModelsCommentSerializer
      end
    end

    let(:association_serializer) do
      define_serializer("AssociationPostSerializer") do
        attributes :title
        has_many :comments, serializer: ModelsCommentSerializer
      end
    end

    before { comment_with(stored, post) }

    it "writes a JSON column of a has_many child as its stored text" do
      json = post_serializer.new.serialize_to_json(Post.find(post.id))

      expect(json).to include(%("meta":#{stored}))
    end

    it "writes a JSON column of a has_one child as its stored text" do
      define_serializer("HasOnePostSerializer") do
        has_one :first_comment, serializer: ModelsCommentSerializer
      end

      json = HasOnePostSerializer.new.serialize_to_json(Post.find(post.id))

      expect(json).to include(%("first_comment":{"id":#{post.comments.first.id},"meta":#{stored}}))
    end

    it "writes the same bytes as the child reached through a real association" do
      record = Post.find(post.id)

      expect(post_serializer.new.serialize_to_json(record)).to eq(association_serializer.new.serialize_to_json(record))
    end

    it "keeps a declared only: filter on the child" do
      define_serializer("FilteredPostSerializer") do
        has_many :visible_comments, name: :comments, serializer: ModelsCommentSerializer, only: [:meta]
      end

      json = FilteredPostSerializer.new.serialize_to_json(Post.find(post.id))

      expect(json).to eq(%({"comments":[{"meta":#{stored}}]}))
    end

    it "serializes a subclass of the declared model with its typed value" do
      store_meta(post.comments.first, nil)
      comment_with(stored, post, model: FlaggedComment)

      metas = meta_texts(post_serializer.new.serialize_to_json(Post.find(post.id)), "comments")

      expect(metas).to eq([nil, Oj.load(stored)])
    end

    it "matches the hash output of the real association" do
      record = Post.find(post.id)

      expect(post_serializer.new.serialize(record)).to eq(association_serializer.new.serialize(record))
    end

    it "is compiled by Panko.compile_all" do
      Panko.compile_all

      expect(post_serializer.new.serialize_to_json(Post.find(post.id))).to include(%("meta":#{stored}))
    end
  end

  context "when the child serializer declares two models" do
    let!(:attachment_serializer) do
      define_serializer("ModelsAttachmentSerializer") do
        models Comment, Note
        attributes :id, :meta
      end
    end

    let!(:post_serializer) do
      define_serializer("ModelsPostSerializer") do
        attributes :title
        has_many :attachments, serializer: ModelsAttachmentSerializer
      end
    end

    before do
      comment_with(stored, post)
      Note.create!(post: post).tap { |note| store_meta(note, other_stored) }
    end

    it "writes each model's JSON column as its stored text, in order" do
      json = post_serializer.new.serialize_to_json(Post.find(post.id))

      expect(json).to include(%("attachments":[{"id":#{post.comments.first.id},"meta":#{stored}},{"id":#{post.notes.first.id},"meta":#{other_stored}}]))
    end

    it "serializes a record of an undeclared class with its typed value" do
      Post.class_eval do
        define_method(:attachments) { comments.to_a + [Struct.new(:id, :meta).new(0, {"k" => 1})] }
      end

      output = Oj.load(post_serializer.new.serialize_to_json(Post.find(post.id)))

      expect(output["attachments"].last).to eq("id" => 0, "meta" => {"k" => 1})
    end

    it "matches the hash output of the typed values" do
      output = post_serializer.new.serialize(Post.find(post.id))

      expect(output["attachments"].map { |item| item["meta"] }).to eq([Oj.load(stored), Oj.load(other_stored)])
    end
  end

  context "when a declared model lacks a field of the child serializer" do
    before do
      Temping.create(:tag) do
        with_columns do |t|
          t.bigint :post_id
        end
      end
      Post.has_many :tags
      Post.class_eval do
        define_method(:labelled) { comments.to_a + tags.to_a }
      end
      comment_with(stored, post)
    end

    it "specializes the other declared models" do
      define_serializer("PartialCommentSerializer") do
        models Comment, Tag
        attributes :id, :meta
      end
      define_serializer("PartialPostSerializer") do
        has_many :visible_comments, name: :comments, serializer: PartialCommentSerializer
      end

      expect(PartialPostSerializer.new.serialize_to_json(Post.find(post.id))).to include(%("meta":#{stored}))
    end

    it "keeps the typed value when the only declared model lacks the field" do
      define_serializer("TagOnlyCommentSerializer") do
        models Tag
        attributes :id, :meta
      end
      define_serializer("TagOnlyPostSerializer") do
        has_many :visible_comments, name: :comments, serializer: TagOnlyCommentSerializer
      end

      expect(TagOnlyPostSerializer.new.serialize_to_json(Post.find(post.id))).to include(%("meta":#{reencoded}))
    end
  end

  context "when the source is a real association" do
    let!(:comment_serializer) do
      define_serializer("ModelsCommentSerializer") do
        models Note
        attributes :id, :meta
      end
    end

    it "specializes the child for the reflected class, not the declared one" do
      define_serializer("ModelsPostSerializer") do
        attributes :title
        has_many :comments, serializer: ModelsCommentSerializer
      end
      comment_with(stored, post)

      expect(ModelsPostSerializer.new.serialize_to_json(Post.find(post.id))).to include(%("meta":#{stored}))
    end
  end

  context "when the child serializer declares no models" do
    it "writes the typed value" do
      define_serializer("PlainCommentSerializer") do
        attributes :id, :meta
      end
      define_serializer("PlainPostSerializer") do
        attributes :title
        has_many :visible_comments, name: :comments, serializer: PlainCommentSerializer
      end
      comment_with(stored, post)

      json = PlainPostSerializer.new.serialize_to_json(Post.find(post.id))

      expect(json).to include(%("meta":#{reencoded}))
    end
  end
end
