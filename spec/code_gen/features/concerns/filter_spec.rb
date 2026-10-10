# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "shallow_generic"
require "shallow_specialized"
require "nested_composition"

RSpec.describe "Filter — :only / :except / co-supplied / empty / unknown / no-inheritance / Source-keyed / filter-before-if: / nested / recursive" do
  def compile(fixture, mode)
    Panko::CodeGen.compile(fixture::DESCRIPTOR, output: mode, config: fixture::CONFIG)
      .new(descriptor: fixture::DESCRIPTOR)
  end

  describe "(1) :only — keeps only the listed Field names" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "Attribute-only Descriptor: keeps only listed Attributes" do
          generated = compile(Fixtures::ShallowGeneric, mode)
          record = Fixtures::ShallowGeneric.sanity_record
          expected = (mode == :json) ? '{"id":1}' : {"id" => 1}
          expect(generated.serialize_one(record, filters: {only: [:id]})).to eq(expected)
        end

        it "Method Attribute Descriptor: keeps only listed Method Attributes" do
          generated = compile(Fixtures::ShallowSpecialized, mode)
          record = Fixtures::ShallowSpecialized.sanity_record
          expected = (mode == :json) ? '{"static":42}' : {"static" => 42}
          expect(generated.serialize_one(record, filters: {only: [:static]})).to eq(expected)
        end

        it "Descriptor with an Association: keeps only the listed Association name" do
          generated = compile(Fixtures::NestedComposition, mode)
          record = Fixtures::NestedComposition.sanity_record
          expected = (mode == :json) ?
            '{"comments":[{"id":11,"body":"first"},{"id":12,"body":"second"}]}' :
            {"comments" => [{"id" => 11, "body" => "first"}, {"id" => 12, "body" => "second"}]}
          expect(generated.serialize_one(record, filters: {only: [:comments]})).to eq(expected)
        end
      end
    end
  end

  describe "(2) :except — drops the listed Field names" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "Attribute-only Descriptor: drops the listed Attribute" do
          generated = compile(Fixtures::ShallowGeneric, mode)
          record = Fixtures::ShallowGeneric.sanity_record
          expected = (mode == :json) ? '{"title":"hi"}' : {"title" => "hi"}
          expect(generated.serialize_one(record, filters: {except: [:id]})).to eq(expected)
        end

        it "Method Attribute Descriptor: drops the listed Method Attribute" do
          generated = compile(Fixtures::ShallowSpecialized, mode)
          record = Fixtures::ShallowSpecialized.sanity_record
          expected = (mode == :json) ?
            '{"id":1,"title":"HI","headline":"HI (id=1)","contextual":null}' :
            {"id" => 1, "title" => "HI", "headline" => "HI (id=1)", "contextual" => nil}
          expect(generated.serialize_one(record, filters: {except: [:static]})).to eq(expected)
        end

        it "Descriptor with an Association: drops the listed Association name" do
          generated = compile(Fixtures::NestedComposition, mode)
          record = Fixtures::NestedComposition.sanity_record
          expected = (mode == :json) ?
            '{"id":1,"author":{"id":7,"name":"alice"}}' :
            {"id" => 1, "author" => {"id" => 7, "name" => "alice"}}
          expect(generated.serialize_one(record, filters: {except: [:comments]})).to eq(expected)
        end
      end
    end
  end

  describe "(3) :only and :except co-supplied at the same level → ArgumentError" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "raises ArgumentError on serialize_one at the first _write_one / _to_hash entry" do
          generated = compile(Fixtures::ShallowGeneric, mode)
          record = Fixtures::ShallowGeneric.sanity_record
          expect {
            generated.serialize_one(record, filters: {only: [:id], except: [:title]})
          }.to raise_error(ArgumentError, /only.*except/i)
        end

        it "raises ArgumentError on serialize_many" do
          generated = compile(Fixtures::ShallowGeneric, mode)
          records = [Fixtures::ShallowGeneric.sanity_record]
          expect {
            generated.serialize_many(records, filters: {only: [:id], except: [:title]})
          }.to raise_error(ArgumentError, /only.*except/i)
        end

        it "raises ArgumentError when co-supplied at a nested Association level" do
          generated = compile(Fixtures::NestedComposition, mode)
          record = Fixtures::NestedComposition.sanity_record
          expect {
            generated.serialize_one(record, filters: {author: {only: [:id], except: [:name]}})
          }.to raise_error(ArgumentError, /only.*except/i)
        end
      end
    end
  end

  describe "(4) Empty Hash {} ≡ nil — no filtering, both route to Filter::None" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "produces output identical to filters: nil for serialize_one" do
          generated = compile(Fixtures::ShallowGeneric, mode)
          record = Fixtures::ShallowGeneric.sanity_record
          expected = Fixtures::ShallowGeneric.expected_output(mode)
          expect(generated.serialize_one(record, filters: nil)).to eq(expected)
          expect(generated.serialize_one(record, filters: {})).to eq(expected)
        end

        it "produces output identical to filters: nil for serialize_many" do
          generated = compile(Fixtures::ShallowGeneric, mode)
          records = [Fixtures::ShallowGeneric.sanity_record]
          expected_one = Fixtures::ShallowGeneric.expected_output(mode)
          expected = (mode == :json) ? "[#{expected_one}]" : [expected_one]
          expect(generated.serialize_many(records, filters: nil)).to eq(expected)
          expect(generated.serialize_many(records, filters: {})).to eq(expected)
        end

        it "routes both filters: nil and filters: {} to the Filter::None singleton" do
          expect(Panko::CodeGen::Filter.wrap(nil)).to equal(Panko::CodeGen::Filter::None)
          expect(Panko::CodeGen::Filter.wrap({})).to equal(Panko::CodeGen::Filter::None)
        end
      end
    end
  end

  describe "(5) Unknown keys at any level — silently ignored (forward-compat)" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "ignores a top-level Field name not present in FIELD_INDEX" do
          generated = compile(Fixtures::ShallowGeneric, mode)
          record = Fixtures::ShallowGeneric.sanity_record
          expected = (mode == :json) ? '{"id":1}' : {"id" => 1}
          expect(
            generated.serialize_one(record, filters: {only: [:id, :nonexistent]})
          ).to eq(expected)
        end

        it "ignores a top-level non-Field key (forward-compat with future filter shapes)" do
          generated = compile(Fixtures::ShallowGeneric, mode)
          record = Fixtures::ShallowGeneric.sanity_record
          expected = Fixtures::ShallowGeneric.expected_output(mode)
          expect(
            generated.serialize_one(record, filters: {future_filter_key: 42})
          ).to eq(expected)
        end

        it "ignores an unknown Source key on a Descriptor with an Association" do
          generated = compile(Fixtures::NestedComposition, mode)
          record = Fixtures::NestedComposition.sanity_record
          expected = Fixtures::NestedComposition.expected_output(mode)
          expect(
            generated.serialize_one(record, filters: {unknown_assoc: {only: [:id]}})
          ).to eq(expected)
        end
      end
    end
  end

  describe "(6) No inheritance — a parent's filter does not implicitly apply to children unless threaded" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "the author child emits all its Fields when the parent restricts to :only [:author]" do
          # Parent :only [:author] drops positions 0 and 2. Passed to the author child as is,
          # it would also drop the author's id (position 0).
          generated = compile(Fixtures::NestedComposition, mode)
          record = Fixtures::NestedComposition.sanity_record
          expected = (mode == :json) ?
            '{"author":{"id":7,"name":"alice"}}' :
            {"author" => {"id" => 7, "name" => "alice"}}
          expect(generated.serialize_one(record, filters: {only: [:author]})).to eq(expected)
        end

        it "the comments children emit all their Fields when the parent restricts to :only [:comments]" do
          generated = compile(Fixtures::NestedComposition, mode)
          record = Fixtures::NestedComposition.sanity_record
          expected = (mode == :json) ?
            '{"comments":[{"id":11,"body":"first"},{"id":12,"body":"second"}]}' :
            {"comments" => [{"id" => 11, "body" => "first"}, {"id" => 12, "body" => "second"}]}
          expect(generated.serialize_one(record, filters: {only: [:comments]})).to eq(expected)
        end
      end
    end
  end

  describe "(7) Child-filter key — looked up by Source, not name (when Source ≠ name)" do
    # Built inline: no shared fixture has an Association whose source differs from its name.
    let(:author_descriptor) do
      Panko::CodeGen::Descriptor.new(
        name: "Source7AuthorSerializer",
        model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [
          Panko::CodeGen::Attribute.new(name: :id, source: :id),
          Panko::CodeGen::Attribute.new(name: :name, source: :name)
        ],
        method_attributes: [],
        associations: []
      )
    end

    let(:post_descriptor) do
      Panko::CodeGen::Descriptor.new(
        name: "Source7PostSerializer",
        model: nil,
        parent_class: Fixtures::BaseSerializer,
        attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
        method_attributes: [],
        associations: [
          Panko::CodeGen::Association.new(
            name: :writer, kind: :has_one, descriptor: author_descriptor, source: :author
          )
        ]
      )
    end

    let(:record) { {"id" => 1, "author" => {"id" => 7, "name" => "alice"}} }

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "scopes the child filter via the Source key (:author), not the name key (:writer)" do
          generated = Panko::CodeGen.compile(post_descriptor, output: mode).new(descriptor: post_descriptor)
          expected = (mode == :json) ?
            '{"id":1,"writer":{"id":7}}' :
            {"id" => 1, "writer" => {"id" => 7}}
          expect(
            generated.serialize_one(record, filters: {author: {only: [:id]}})
          ).to eq(expected)
        end

        it "ignores a sub-filter keyed by name (:writer) when Source is :author (forward-compat silent ignore)" do
          generated = Panko::CodeGen.compile(post_descriptor, output: mode).new(descriptor: post_descriptor)
          expected = (mode == :json) ?
            '{"id":1,"writer":{"id":7,"name":"alice"}}' :
            {"id" => 1, "writer" => {"id" => 7, "name" => "alice"}}
          expect(
            generated.serialize_one(record, filters: {writer: {only: [:id]}})
          ).to eq(expected)
        end
      end
    end
  end

  describe "(8) Filter-before-if: — a filter-dropped Association does not invoke its if: Callable" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        def build_with_spy(spy)
          author_d = Panko::CodeGen::Descriptor.new(
            name: "FilterBeforeIfAuthorSerializer",
            model: nil,
            parent_class: Fixtures::BaseSerializer,
            attributes: [
              Panko::CodeGen::Attribute.new(name: :id, source: :id),
              Panko::CodeGen::Attribute.new(name: :name, source: :name)
            ],
            method_attributes: [],
            associations: []
          )
          comment_d = Panko::CodeGen::Descriptor.new(
            name: "FilterBeforeIfCommentSerializer",
            model: nil,
            parent_class: Fixtures::BaseSerializer,
            attributes: [
              Panko::CodeGen::Attribute.new(name: :id, source: :id),
              Panko::CodeGen::Attribute.new(name: :body, source: :body)
            ],
            method_attributes: [],
            associations: []
          )
          Panko::CodeGen::Descriptor.new(
            name: "FilterBeforeIfPostSerializer",
            model: nil,
            parent_class: Fixtures::BaseSerializer,
            attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
            method_attributes: [],
            associations: [
              Panko::CodeGen::Association.new(
                name: :author, kind: :has_one, descriptor: author_d,
                if: ->(_record, _context) {
                  spy << :invoked
                  true
                }
              ),
              Panko::CodeGen::Association.new(
                name: :comments, kind: :has_many, descriptor: comment_d
              )
            ]
          )
        end

        let(:record) {
          {
            "id" => 1,
            "author" => {"id" => 7, "name" => "alice"},
            "comments" => [{"id" => 11, "body" => "first"}]
          }
        }

        it "does not invoke if: when the Association is dropped via :except" do
          spy = []
          d = build_with_spy(spy)
          generated = Panko::CodeGen.compile(d, output: mode).new(descriptor: d)
          generated.serialize_one(record, filters: {except: [:author]})
          expect(spy).to be_empty
        end

        it "does not invoke if: when the Association is omitted from :only" do
          spy = []
          d = build_with_spy(spy)
          generated = Panko::CodeGen.compile(d, output: mode).new(descriptor: d)
          generated.serialize_one(record, filters: {only: [:id, :comments]})
          expect(spy).to be_empty
        end

        it "invokes if: exactly once on the filter-kept path (control)" do
          # Control: proves the spy works, so the empty spies above come from the filter.
          spy = []
          d = build_with_spy(spy)
          generated = Panko::CodeGen.compile(d, output: mode).new(descriptor: d)
          generated.serialize_one(record)
          expect(spy.size).to eq(1)
        end

        it "does not invoke if: across N records when serialize_many drops the Association" do
          spy = []
          d = build_with_spy(spy)
          generated = Panko::CodeGen.compile(d, output: mode).new(descriptor: d)
          records = [record, record.merge("id" => 2), record.merge("id" => 3)]
          generated.serialize_many(records, filters: {except: [:author]})
          expect(spy).to be_empty
        end
      end
    end
  end

  describe "(9) Nested-Composition filter scoping — sub-filter actually filters the child" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "applies :only on a has_one Association sub-filter" do
          generated = compile(Fixtures::NestedComposition, mode)
          record = Fixtures::NestedComposition.sanity_record
          expected = (mode == :json) ?
            '{"id":1,"author":{"id":7},' \
              '"comments":[{"id":11,"body":"first"},{"id":12,"body":"second"}]}' :
            {
              "id" => 1,
              "author" => {"id" => 7},
              "comments" => [
                {"id" => 11, "body" => "first"},
                {"id" => 12, "body" => "second"}
              ]
            }
          expect(generated.serialize_one(record, filters: {author: {only: [:id]}})).to eq(expected)
        end

        it "applies :except on a has_many Association sub-filter" do
          generated = compile(Fixtures::NestedComposition, mode)
          record = Fixtures::NestedComposition.sanity_record
          expected = (mode == :json) ?
            '{"id":1,"author":{"id":7,"name":"alice"},' \
              '"comments":[{"body":"first"},{"body":"second"}]}' :
            {
              "id" => 1,
              "author" => {"id" => 7, "name" => "alice"},
              "comments" => [{"body" => "first"}, {"body" => "second"}]
            }
          expect(generated.serialize_one(record, filters: {comments: {except: [:id]}})).to eq(expected)
        end

        it "scopes parent and child sub-filters independently when supplied at both levels" do
          generated = compile(Fixtures::NestedComposition, mode)
          record = Fixtures::NestedComposition.sanity_record
          expected = (mode == :json) ?
            '{"author":{"name":"alice"},"comments":[{"id":11},{"id":12}]}' :
            {
              "author" => {"name" => "alice"},
              "comments" => [{"id" => 11}, {"id" => 12}]
            }
          expect(
            generated.serialize_one(
              record,
              filters: {
                only: [:author, :comments],
                author: {except: [:id]},
                comments: {only: [:id]}
              }
            )
          ).to eq(expected)
        end
      end
    end
  end

  describe "(10a) Recursive-Descriptor filtering — self-recursion (recursive_self)" do
    require "recursive_self"

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:record) {
          {
            "id" => 1,
            "body" => "root",
            "replies" => [
              {"id" => 2, "body" => "c1", "replies" => [
                {"id" => 4, "body" => "c1.1", "replies" => []}
              ]},
              {"id" => 3, "body" => "c2", "replies" => []}
            ]
          }
        }
        let(:generated) { compile(Fixtures::RecursiveSelf, mode) }

        it "applies a level-1 :only on replies — keeps id+body, drops nested replies on each reply" do
          expected = (mode == :json) ?
            '{"id":1,"body":"root","replies":[' \
              '{"id":2,"body":"c1"},' \
              '{"id":3,"body":"c2"}' \
              "]}" :
            {
              "id" => 1, "body" => "root",
              "replies" => [
                {"id" => 2, "body" => "c1"},
                {"id" => 3, "body" => "c2"}
              ]
            }
          expect(
            generated.serialize_one(record, filters: {replies: {only: [:id, :body]}})
          ).to eq(expected)
        end

        it "applies a level-2 :only via nested {replies: {replies: ...}} — only the inner cycle is scoped" do
          expected = (mode == :json) ?
            '{"id":1,"body":"root","replies":[' \
              '{"id":2,"body":"c1","replies":[{"body":"c1.1"}]},' \
              '{"id":3,"body":"c2","replies":[]}' \
              "]}" :
            {
              "id" => 1, "body" => "root",
              "replies" => [
                {"id" => 2, "body" => "c1", "replies" => [{"body" => "c1.1"}]},
                {"id" => 3, "body" => "c2", "replies" => []}
              ]
            }
          expect(
            generated.serialize_one(record, filters: {replies: {replies: {only: [:body]}}})
          ).to eq(expected)
        end
      end
    end
  end

  describe "(10b) Recursive-Descriptor filtering — mutual recursion (recursive_mutual)" do
    require "recursive_mutual"

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        let(:record) {
          {
            "id" => 1,
            "name" => "root",
            "items" => [
              {
                "id" => 10,
                "name" => "item-1",
                "subfolder" => {
                  "id" => 2,
                  "name" => "inner",
                  "items" => [
                    {"id" => 20, "name" => "deep-item", "subfolder" => nil}
                  ]
                }
              }
            ]
          }
        }
        let(:generated) { compile(Fixtures::RecursiveMutual, mode) }

        it "scopes the level-1 items sub-filter without bleeding into the inner subfolder cycle" do
          expected_inner_folder = {"id" => 2, "name" => "inner", "items" => [
            {"id" => 20, "name" => "deep-item", "subfolder" => nil}
          ]}
          expected_inner_folder_json = '{"id":2,"name":"inner","items":[' \
            '{"id":20,"name":"deep-item","subfolder":null}' \
            "]}"
          expected = (mode == :json) ?
            "{\"id\":1,\"name\":\"root\",\"items\":[" \
              "{\"id\":10,\"subfolder\":#{expected_inner_folder_json}}" \
              "]}" :
            {
              "id" => 1, "name" => "root",
              "items" => [{"id" => 10, "subfolder" => expected_inner_folder}]
            }
          expect(
            generated.serialize_one(
              record, filters: {items: {only: [:id, :subfolder]}}
            )
          ).to eq(expected)
        end

        it "applies a deep nested filter at the Folder cycle's second hop (items → subfolder → items)" do
          expected = (mode == :json) ?
            '{"id":1,"name":"root","items":[' \
              '{"id":10,"name":"item-1","subfolder":{"id":2,"name":"inner","items":[' \
              '{"id":20}' \
              "]}}" \
              "]}" :
            {
              "id" => 1, "name" => "root",
              "items" => [{
                "id" => 10, "name" => "item-1",
                "subfolder" => {
                  "id" => 2, "name" => "inner",
                  "items" => [{"id" => 20}]
                }
              }]
            }
          expect(
            generated.serialize_one(
              record,
              filters: {items: {subfolder: {items: {only: [:id]}}}}
            )
          ).to eq(expected)
        end
      end
    end
  end

  describe "(11) shared Source across two Associations — child cell scoped per child FIELD_INDEX" do
    first_child = Panko::CodeGen::Descriptor.new(
      name: "FilterSharedSourceFirstChildSerializer",
      model: nil,
      parent_class: Fixtures::BaseSerializer,
      attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
      method_attributes: [],
      associations: []
    )

    second_child = Panko::CodeGen::Descriptor.new(
      name: "FilterSharedSourceSecondChildSerializer",
      model: nil,
      parent_class: Fixtures::BaseSerializer,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :body, source: :body),
        Panko::CodeGen::Attribute.new(name: :id, source: :id)
      ],
      method_attributes: [],
      associations: []
    )

    parent = Panko::CodeGen::Descriptor.new(
      name: "FilterSharedSourceParentSerializer",
      model: nil,
      parent_class: Fixtures::BaseSerializer,
      attributes: [],
      method_attributes: [],
      associations: [
        Panko::CodeGen::Association.new(name: :recent, kind: :has_one, descriptor: first_child, source: :comments),
        Panko::CodeGen::Association.new(name: :all, kind: :has_one, descriptor: second_child, source: :comments)
      ]
    )

    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "narrows each Association against its own child's FIELD_INDEX" do
          generated = Panko::CodeGen.compile(parent, output: mode, config: Panko::CodeGen::Config.new)
            .new(descriptor: parent)
          record = {"comments" => {"id" => 1, "body" => "hidden"}}

          # The two children put :id at different FIELD_INDEX positions, so a child
          # cell cached per Source alone would leak the second child's :body.
          expected = (mode == :json) ?
            '{"recent":{"id":1},"all":{"id":1}}' :
            {"recent" => {"id" => 1}, "all" => {"id" => 1}}
          expect(
            generated.serialize_one(record, filters: {comments: {only: [:id]}})
          ).to eq(expected)
        end
      end
    end
  end
end
