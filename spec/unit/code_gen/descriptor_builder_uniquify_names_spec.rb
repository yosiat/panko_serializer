# frozen_string_literal: true

require "spec_helper"

describe "Panko::CodeGen::DescriptorBuilder.uniquify_names" do
  before do
    Temping.create(:post) do
      with_columns do |t|
        t.string :title
      end
    end
    Temping.create(:comment) do
      with_columns do |t|
        t.bigint :post_id
      end
    end
    Temping.create(:note) do
      with_columns do |t|
        t.bigint :post_id
      end
    end
    Post.has_many :comments
    Post.has_many :notes
    Post.class_eval do
      define_method(:attachments) { comments.to_a + notes.to_a }
      define_method(:pinned) { comments.first }
    end

    stub_const("UniqueAttachmentSerializer", Class.new(Panko::Serializer) do
      models Comment, Note
      attributes :id
    end)
  end

  let(:post_serializer) do
    stub_const("UniquePostSerializer", Class.new(Panko::Serializer) do
      attributes :title
      has_many :attachments, serializer: UniqueAttachmentSerializer
      has_one :pinned, serializer: UniqueAttachmentSerializer
    end)
  end

  let(:specialized) do
    base = Panko::CodeGen::SerializerCache.descriptor_for(post_serializer)
    Panko::CodeGen::DescriptorBuilder.uniquify_names(Panko::CodeGen::DescriptorBuilder.specialize(base, Post))
  end

  let(:attachments) { specialized.associations.first }
  let(:pinned) { specialized.associations.last }

  it "shares each variant between associations that specialize the child the same way" do
    expect(attachments.variants.zip(pinned.variants)).to all(satisfy { |left, right| left.equal?(right) })
  end

  it "keeps one variant per record class" do
    expect(attachments.variants.map(&:model)).to eq([Comment, Note])
    expect(attachments.variants.map(&:name).uniq.size).to eq(attachments.variants.size)
  end

  it "keeps the unspecialized child apart from its variants" do
    expect(attachments.variants.map(&:name)).not_to include(attachments.descriptor.name)
  end
end
