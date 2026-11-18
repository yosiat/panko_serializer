# frozen_string_literal: true

require "spec_helper"

# A serializer's instance variables last for one serialize call: an
# ArraySerializer call shares them across its records, the next call starts clean.
describe "Instance variables set by method attributes" do
  let(:post_class) { Struct.new(:id, :author, :comments) }
  let(:author_class) { Struct.new(:id) }
  let(:first_post) { post_class.new(1) }
  let(:second_post) { post_class.new(2) }

  def serialize_all_ways(serializer_class, record, **options)
    [
      serializer_class.new(**options).serialize(record),
      Oj.load(serializer_class.new(**options).serialize_to_json(record))
    ]
  end

  context "with an ||= memo" do
    before do
      stub_const("MemoPostSerializer", Class.new(Panko::Serializer) do
        attributes :id, :label

        def label
          @label ||= "Post #{object.id}"
        end
      end)
    end

    it "computes the memo again on the next serialize" do
      serialize_all_ways(MemoPostSerializer, first_post)

      expect(serialize_all_ways(MemoPostSerializer, second_post))
        .to all(eq("id" => 2, "label" => "Post 2"))
    end

    it "computes the memo again on the next write_json" do
      MemoPostSerializer.new.serialize_to_json(first_post)

      writer = Oj::StringWriter.new(mode: :rails)
      MemoPostSerializer.new.write_json(second_post, writer)

      expect(Oj.load(writer.to_s)).to eq("id" => 2, "label" => "Post 2")
    end

    it "computes the memo again on the next ArraySerializer call" do
      Panko::ArraySerializer.new([first_post], each_serializer: MemoPostSerializer).to_a

      result = Panko::ArraySerializer.new([second_post], each_serializer: MemoPostSerializer).to_a

      expect(result).to eq([{"id" => 2, "label" => "Post 2"}])
    end

    it "shares the memo across the records of one ArraySerializer call" do
      result = Panko::ArraySerializer.new([first_post, second_post], each_serializer: MemoPostSerializer).to_a

      expect(result.map { |row| row["label"] }).to eq(["Post 1", "Post 1"])
    end
  end

  it "computes the memo again after a serialize that raised" do
    stub_const("RaisingMemoPostSerializer", Class.new(Panko::Serializer) do
      attributes :label, :check

      def label
        @label ||= "Post #{object.id}"
      end

      def check
        raise "boom" if object.id == :boom
        true
      end
    end)

    expect { RaisingMemoPostSerializer.new.serialize(post_class.new(:boom)) }.to raise_error(RuntimeError, "boom")

    expect(RaisingMemoPostSerializer.new.serialize(second_post)).to eq("label" => "Post 2", "check" => true)
  end

  it "computes a defined? memo again, including one that memoized nil" do
    stub_const("DefinedMemoPostSerializer", Class.new(Panko::Serializer) do
      attributes :id, :label

      def label
        return @label if defined?(@label)
        @label = (object.id == 1) ? nil : "Post #{object.id}"
      end
    end)

    serialize_all_ways(DefinedMemoPostSerializer, first_post)

    expect(serialize_all_ways(DefinedMemoPostSerializer, second_post))
      .to all(eq("id" => 2, "label" => "Post 2"))
  end

  it "computes a memo again when a helper method sets it" do
    stub_const("HelperMemoPostSerializer", Class.new(Panko::Serializer) do
      attributes :id, :label

      def label
        "Post #{post_id}"
      end

      def post_id
        @post_id ||= object.id
      end
    end)

    serialize_all_ways(HelperMemoPostSerializer, first_post)

    expect(serialize_all_ways(HelperMemoPostSerializer, second_post))
      .to all(eq("id" => 2, "label" => "Post 2"))
  end

  it "computes a memo again when an included module sets it" do
    labeling = Module.new do
      def post_label
        @post_label ||= "Post #{object.id}"
      end
    end
    stub_const("ModuleMemoPostSerializer", Class.new(Panko::Serializer) do
      include labeling

      attributes :id, :label

      def label
        post_label
      end
    end)

    serialize_all_ways(ModuleMemoPostSerializer, first_post)

    expect(serialize_all_ways(ModuleMemoPostSerializer, second_post))
      .to all(eq("id" => 2, "label" => "Post 2"))
  end

  it "computes a memo again when a parent serializer sets it" do
    stub_const("ParentMemoSerializer", Class.new(Panko::Serializer) do
      def post_label
        @post_label ||= "Post #{object.id}"
      end
    end)
    stub_const("ChildMemoPostSerializer", Class.new(ParentMemoSerializer) do
      attributes :id, :label

      def label
        post_label
      end
    end)

    serialize_all_ways(ChildMemoPostSerializer, first_post)

    expect(serialize_all_ways(ChildMemoPostSerializer, second_post))
      .to all(eq("id" => 2, "label" => "Post 2"))
  end

  it "computes a memo again when define_method sets it" do
    stub_const("DefineMethodMemoPostSerializer", Class.new(Panko::Serializer) do
      attributes :id, :label

      define_method(:label) { @label ||= "Post #{object.id}" }
    end)

    serialize_all_ways(DefineMethodMemoPostSerializer, first_post)

    expect(serialize_all_ways(DefineMethodMemoPostSerializer, second_post))
      .to all(eq("id" => 2, "label" => "Post 2"))
  end

  it "computes a memo again when instance_variable_set sets it" do
    stub_const("DynamicMemoPostSerializer", Class.new(Panko::Serializer) do
      attributes :id, :label

      def label
        name = :"@label_#{object.id.class.name.downcase}"
        return instance_variable_get(name) if instance_variable_defined?(name)
        instance_variable_set(name, "Post #{object.id}")
      end
    end)

    serialize_all_ways(DynamicMemoPostSerializer, first_post)

    expect(serialize_all_ways(DynamicMemoPostSerializer, second_post))
      .to all(eq("id" => 2, "label" => "Post 2"))
  end

  it "computes a memo again when an attr_writer sets it" do
    stub_const("WriterMemoPostSerializer", Class.new(Panko::Serializer) do
      attr_accessor :cached_label

      attributes :id, :label

      def label
        self.cached_label ||= "Post #{object.id}"
      end
    end)

    serialize_all_ways(WriterMemoPostSerializer, first_post)

    expect(serialize_all_ways(WriterMemoPostSerializer, second_post))
      .to all(eq("id" => 2, "label" => "Post 2"))
  end

  it "computes a memo again when it holds a per-request context value" do
    stub_const("ContextMemoPostSerializer", Class.new(Panko::Serializer) do
      attributes :id, :label

      def label
        @prefix ||= context[:prefix]
        "#{@prefix} #{object.id}"
      end
    end)

    serialize_all_ways(ContextMemoPostSerializer, first_post, context: {prefix: "A"})

    expect(serialize_all_ways(ContextMemoPostSerializer, second_post, context: {prefix: "B"}))
      .to all(eq("id" => 2, "label" => "B 2"))
  end

  context "with a memo in an association serializer" do
    before do
      stub_const("MemoAuthorSerializer", Class.new(Panko::Serializer) do
        attributes :id, :label

        def label
          @label ||= "Author #{object.id}"
        end
      end)
      stub_const("AuthoredPostSerializer", Class.new(Panko::Serializer) do
        attributes :id
        has_one :author, serializer: MemoAuthorSerializer
        has_many :comments, each_serializer: MemoAuthorSerializer
      end)
    end

    it "computes the child's memo again on the next serialize of the parent" do
      first = post_class.new(1, author_class.new(10), [author_class.new(11)])
      second = post_class.new(2, author_class.new(20), [author_class.new(21)])
      serialize_all_ways(AuthoredPostSerializer, first)

      expect(serialize_all_ways(AuthoredPostSerializer, second)).to all(eq(
        "id" => 2,
        "author" => {"id" => 20, "label" => "Author 20"},
        "comments" => [{"id" => 21, "label" => "Author 21"}]
      ))
    end
  end

  context "with an ActiveRecord model" do
    before do
      Temping.create(:memo_foo) do
        with_columns do |t|
          t.string :name
        end
      end
      stub_const("MemoFooSerializer", Class.new(Panko::Serializer) do
        attributes :name, :label

        def label
          @label ||= "Foo #{object.name}"
        end
      end)
    end

    it "computes the memo again on the next serialize" do
      serialize_all_ways(MemoFooSerializer, MemoFoo.create!(name: "a"))

      expect(serialize_all_ways(MemoFooSerializer, MemoFoo.create!(name: "b")))
        .to all(eq("name" => "b", "label" => "Foo b"))
    end
  end

  context "with ActiveRecord parents and children" do
    before do
      Temping.create(:memo_shelf) do
        with_columns do |t|
          t.string :name
        end
      end
      Temping.create(:memo_book) do
        with_columns do |t|
          t.string :title
          t.bigint :memo_shelf_id
        end
      end
      MemoShelf.has_many :memo_books
      MemoShelf.has_one :memo_book
      MemoBook.belongs_to :memo_shelf, optional: true
      stub_const("MemoBookSerializer", Class.new(Panko::Serializer) do
        attributes :title, :label

        def label
          @label ||= "Book #{object.title}"
        end
      end)
    end

    def shelf(name)
      record = MemoShelf.create!(name: name)
      record.memo_books.create!(title: "#{name}1")
      record.reload
    end

    it "computes a nested child's memo again on the next serialize" do
      stub_const("MemoShelfSerializer", Class.new(Panko::Serializer) do
        attributes :name
        has_many :memo_books, serializer: MemoBookSerializer
      end)
      serialize_all_ways(MemoShelfSerializer, shelf("a"))

      expect(serialize_all_ways(MemoShelfSerializer, shelf("b"))).to all(eq(
        "name" => "b", "memo_books" => [{"title" => "b1", "label" => "Book b1"}]
      ))
    end

    it "keeps the generated children and guards when instance_variable_set sets a memo" do
      stub_const("DynamicMemoShelfSerializer", Class.new(Panko::Serializer) do
        attributes :name, :label
        has_one :memo_book, serializer: MemoBookSerializer, if: ->(_record, context) { context[:with_book] }
        has_many :memo_books, serializer: MemoBookSerializer

        def label
          instance_variable_set(:@label, "Shelf #{object.name}") unless instance_variable_defined?(:@label)
          @label
        end
      end)
      context = {context: {with_book: true}}
      serialize_all_ways(DynamicMemoShelfSerializer, shelf("a"), **context)

      expect(serialize_all_ways(DynamicMemoShelfSerializer, shelf("b"), **context)).to all(eq(
        "name" => "b", "label" => "Shelf b",
        "memo_book" => {"title" => "b1", "label" => "Book b1"},
        "memo_books" => [{"title" => "b1", "label" => "Book b1"}]
      ))
    end
  end

  it "keeps serializing after many calls that set and clear a memo" do
    stub_const("ChurnMemoPostSerializer", Class.new(Panko::Serializer) do
      attributes :id, :label

      def label
        @label ||= "Post #{object.id}"
      end
    end)

    labels = (1..50).map { |id| ChurnMemoPostSerializer.new.serialize(post_class.new(id))["label"] }

    expect(labels).to eq((1..50).map { |id| "Post #{id}" })
  end
end
