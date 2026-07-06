# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "shallow_generic"
require "shallow_specialized"
require "nested_composition"

# Cross-cutting +Filter+ contract — the 10-item enumeration from
# +docs/testing.md § filter_spec.rb+. JSON/Hash parity (item 10) is
# iterated at every describe block per
# +docs/testing.md § JSON/Hash parity+ (the same file holds both modes
# rather than splitting per-mode files — divergence between modes would
# be a regression worth catching at the spec tier).
#
# Fixture strategy mirrors +docs/testing.md § filter_spec.rb § Fixture
# strategy+:
#
# - +shallow_generic+ for the Attributes-only +:only+ / +:except+
#   stories;
# - +shallow_specialized+ for the Method-Attribute coverage of +:only+
#   / +:except+ (its 3 Method Attributes already pin the SKIP /
#   reader-override / context shape from S6 — this file uses them as
#   filter targets);
# - +nested_composition+ for the no-inheritance and threading-through-
#   +Composition+ stories (the fixture's +has_one :author+ + +has_many
#   :comments+ matches the precedence-ladder shape from
#   +docs/testing.md § association_if_spec.rb+);
# - inline minimal Descriptors when the canonical corpus does not
#   carry the right shape (the +Source ≠ name+ case + the
#   filter-before-+if:+ spy + the recursive-Descriptor cases).
#
# Per S14.3 acceptance: validation lives at +Filter.wrap+, runs once
# per +serialize_*+ call, and the emitted +_write_one+ / +_to_hash+
# bodies stay free of validation branches. Per S14.4 acceptance:
# +filters.child(:<source>, <Child>::FIELD_INDEX)+ scopes a real child
# cell at every nested call site so sub-filters actually filter, and
# the filter-before-+if:+ ordering pins a filter-dropped Association
# from invoking its +if:+ Callable.
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
            '{"id":1,"title":"hi","headline":"HI (id=1)","contextual":null}' :
            {"id" => 1, "title" => "hi", "headline" => "HI (id=1)", "contextual" => nil}
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

  describe "(4) Empty Hash {} ≡ nil — no filtering, both route to Filter::NONE" do
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

        it "routes both filters: nil and filters: {} to the Filter::NONE singleton" do
          # Pinned at the public-API tier per S14.3 acceptance ("filters:
          # nil and filters: {} route to Filter::NONE"). The +Filter.wrap+
          # call inside +serialize_one+ is the only place that decides
          # this; if a future refactor accidentally allocates a fresh
          # Indexed cell for the empty-Hash path, the +equal?+ assertion
          # below catches it.
          expect(Panko::CodeGen::Filter.wrap(nil)).to equal(Panko::CodeGen::Filter::NONE)
          expect(Panko::CodeGen::Filter.wrap({})).to equal(Panko::CodeGen::Filter::NONE)
        end
      end
    end
  end

  describe "(5) Unknown keys at any level — silently ignored (forward-compat)" do
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "ignores a top-level Field name not present in FIELD_INDEX" do
          # +:nonexistent+ is not in +ShallowGeneric+'s FIELD_INDEX
          # +{id, title}+; per +docs/filters.md § Rules+ ("A key that
          # does not match any node at its level is ignored silently"),
          # the only-list still scopes the output to +:id+ alone.
          generated = compile(Fixtures::ShallowGeneric, mode)
          record = Fixtures::ShallowGeneric.sanity_record
          expected = (mode == :json) ? '{"id":1}' : {"id" => 1}
          expect(
            generated.serialize_one(record, filters: {only: [:id, :nonexistent]})
          ).to eq(expected)
        end

        it "ignores a top-level non-Field key (forward-compat with future filter shapes)" do
          # +:future_filter_key+ is not a recognized top-level filter
          # operator (today only +:only+ / +:except+ + Association
          # sub-hashes are recognized). Caller passes it; library
          # silently ignores; output is unfiltered.
          generated = compile(Fixtures::ShallowGeneric, mode)
          record = Fixtures::ShallowGeneric.sanity_record
          expected = Fixtures::ShallowGeneric.expected_output(mode)
          expect(
            generated.serialize_one(record, filters: {future_filter_key: 42})
          ).to eq(expected)
        end

        it "ignores an unknown Source key on a Descriptor with an Association" do
          # +:unknown_assoc+ is not an Association on +nested_composition+
          # (whose Sources are +:author+ and +:comments+); the sub-hash
          # is silently ignored. Output is unfiltered.
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
    # Per +docs/filters.md § Rules+ ("Filters do not inherit: +:only+
    # at the parent level does not propagate to child Associations.").
    # The trap below: the parent's bit pattern at child-shared indices
    # would silently drop the child's Fields if the parent's Filter
    # object were passed verbatim to the nested +_write_one+ /
    # +_to_hash+. The S14.3 +filters.child(:<source>)+ threading
    # rescopes the nested call to +Filter::NONE+ when the caller
    # supplied no sub-hash for that Source — the child is unfiltered,
    # not parent-bit-shifted.
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "the author child emits all its Fields when the parent restricts to :only [:author]" do
          # Parent FIELD_INDEX = {id: 0, author: 1, comments: 2}.
          # Parent +:only [:author]+ → drops_mask = bit 0 (id) + bit 2
          # (comments) = 0b101. If the child Author serializer received
          # that mask verbatim, +filters.drops?(0)+ would return +true+
          # and the author's +id+ Field would be dropped — that is the
          # inheritance bug this test guards against.
          generated = compile(Fixtures::NestedComposition, mode)
          record = Fixtures::NestedComposition.sanity_record
          expected = (mode == :json) ?
            '{"author":{"id":7,"name":"alice"}}' :
            {"author" => {"id" => 7, "name" => "alice"}}
          expect(generated.serialize_one(record, filters: {only: [:author]})).to eq(expected)
        end

        it "the comments children emit all their Fields when the parent restricts to :only [:comments]" do
          # Parent +:only [:comments]+ → drops_mask = 0b011 (drops id +
          # author). For each comment child (FIELD_INDEX = {id, body}),
          # the inherited mask would drop +id+ (bit 0 = 1) and keep
          # +body+ (bit 1 = 0). With +filters.child(:comments)+
          # threading, each comment is serialized under +Filter::NONE+
          # and emits both Fields.
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
    # Per +docs/filters.md § Rules+ ("Child-filter keys reference the
    # Association's Source (which defaults to the name unless explicitly
    # overridden)"). Built inline because the canonical corpus has every
    # Association at +source == name+; the +Source ≠ name+ shape only
    # exists when an Association explicitly overrides +source:+. The
    # parent emit at S14.4 threads +filters.child(:#{association.source},
    # ChildClass::FIELD_INDEX)+ — the Source is the lookup key per
    # +docs/filters.md § Threading through Composition+, the +name+ is
    # the output key.
    let(:author_descriptor) do
      Panko::CodeGen::Descriptor.new(
        name: "Source7AuthorSerializer",
        models: nil,
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
        models: nil,
        attributes: [Panko::CodeGen::Attribute.new(name: :id, source: :id)],
        method_attributes: [],
        associations: [
          # +name: :writer+ → output key in JSON / Hash is +"writer"+.
          # +source: :author+ → +Source+ is +:author+; the parent reads
          # +record["author"]+ and the child filter is keyed by
          # +:author+, not +:writer+.
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
          # Sub-filter keyed by Source +:author+ → restricts the writer
          # child to +:id+ only. If the lookup were keyed by +:name+
          # (the +name+), this sub-hash would silently miss the author
          # subtree (no +writer+ key in the filter Hash) and the writer
          # would emit unfiltered.
          expected = (mode == :json) ?
            '{"id":1,"writer":{"id":7}}' :
            {"id" => 1, "writer" => {"id" => 7}}
          expect(
            generated.serialize_one(record, filters: {author: {only: [:id]}})
          ).to eq(expected)
        end

        it "ignores a sub-filter keyed by name (:writer) when Source is :author (forward-compat silent ignore)" do
          # Inverse pinning of the rule: the +name+-keyed sub-filter
          # does not match the Source-keyed lookup, so it is silently
          # ignored per +docs/filters.md § Rules+ ("A key that does not
          # match any node at its level is ignored silently"). The
          # writer child emits unfiltered.
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
    # Per +docs/filters.md § Filter before if:+ + the precedence ladder
    # in +docs/testing.md § association_if_spec.rb § Precedence ladder+
    # (item 1 wins over item 2): when the +Filter+ drops an Association
    # the +if:+ Callable is not invoked, the Source is not loaded, and
    # the nested Generated Class is not entered. Spy +if:+ Callable
    # counts invocations — pinning cardinality at zero on the
    # filter-dropped path and at one on the filter-kept path. Built
    # inline against the +nested_composition+ shape (+has_one :author+
    # with +if:+ + +has_many :comments+) so the +if:+-bearing
    # Association is the dropped target.
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        # Each test builds a Descriptor with a fresh spy on the +if:+
        # Callable to keep state-leak across iterations zero (each
        # +has_one :author+ + +if:+ + +has_many :comments+ shape mirrors
        # +nested_composition+ but parameterized on the spy).
        def build_with_spy(spy)
          author_d = Panko::CodeGen::Descriptor.new(
            name: "FilterBeforeIfAuthorSerializer",
            models: nil,
            attributes: [
              Panko::CodeGen::Attribute.new(name: :id, source: :id),
              Panko::CodeGen::Attribute.new(name: :name, source: :name)
            ],
            method_attributes: [],
            associations: []
          )
          comment_d = Panko::CodeGen::Descriptor.new(
            name: "FilterBeforeIfCommentSerializer",
            models: nil,
            attributes: [
              Panko::CodeGen::Attribute.new(name: :id, source: :id),
              Panko::CodeGen::Attribute.new(name: :body, source: :body)
            ],
            method_attributes: [],
            associations: []
          )
          Panko::CodeGen::Descriptor.new(
            name: "FilterBeforeIfPostSerializer",
            models: nil,
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
          # Sanity: with no filter, the +if:+ Callable is invoked once
          # per Record per +docs/testing.md § association_if_spec.rb+
          # item 9. Pinned here so the zero-invocation tests above
          # demonstrate filter-induced suppression, not a broken spy.
          spy = []
          d = build_with_spy(spy)
          generated = Panko::CodeGen.compile(d, output: mode).new(descriptor: d)
          generated.serialize_one(record)
          expect(spy.size).to eq(1)
        end

        it "does not invoke if: across N records when serialize_many drops the Association" do
          # Cardinality pin: with N records and an Association dropped
          # by +:except+, the spy must observe zero calls — not N.
          # Mirror of +association_if_spec.rb+ item 9's
          # +serialize_many+ × N test, but on the filter-dropped path.
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
    # Pins the S14.4 functional contract: +filters.child(:#{source},
    # ChildClass::FIELD_INDEX)+ materializes a real child Indexed cell
    # against the nested Generated Class's +FIELD_INDEX+, so a sub-Hash
    # supplied by the caller actually filters the nested call's output.
    # In S14.2 the resolver collapsed every non-empty sub-Hash to
    # +Filter::NONE+ for lack of a child +FIELD_INDEX+ to wrap against;
    # S14.4 threads the constant at the nested call site so the cell
    # finally materializes.
    %i[json hash].each do |mode|
      context "with #{mode} Output Mode" do
        it "applies :only on a has_one Association sub-filter" do
          generated = compile(Fixtures::NestedComposition, mode)
          record = Fixtures::NestedComposition.sanity_record
          # Author FIELD_INDEX = {id: 0, name: 1}. +only: [:id]+ drops
          # +:name+, keeps +:id+.
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
          # Comment FIELD_INDEX = {id: 0, body: 1}. +except: [:id]+
          # drops +:id+ on every comment element, keeps +:body+.
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
          # Combined parent-level +:only [:author, :comments]+ (drops
          # parent +:id+) plus child-level sub-filters on each
          # Association. Pins that parent-level filtering and child-
          # level sub-filtering compose correctly without bleed.
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

  # Per +docs/filters.md § Threading through Composition+: filters thread
  # through +Composition+ at every nested call site, including
  # self-recursion (+recursive_self+: +Comment has_many :replies+ → same
  # +CommentDescriptor+) and mutual recursion (+recursive_mutual+:
  # +Folder → Item → Folder+). At each level the parent's
  # +filters.child(:<source>, FIELD_INDEX)+ scopes the next call to the
  # caller-supplied sub-Hash for that Source — when no sub-Hash is
  # supplied, the +Filter::NONE+ singleton propagates and the subtree
  # below runs unfiltered. The child Filter cache (S14.2) ensures that a
  # deep-nested cycle pays the +Indexed.build+ cost at most once per
  # +(level × Source)+ pair per +serialize_*+ call.
  #
  # Recursive fixtures land in two describe blocks (item 10 split by
  # cycle shape) to keep the RSpec nesting depth at 3 (top describe →
  # item describe → mode context).
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
          # Parent unfiltered; the +replies+ sub-filter scopes the
          # nested +Comment+ Generated Class to +:only [:id, :body]+
          # → drops the nested +:replies+ Field on each level-1
          # element. The level-2 +c1.1+ never appears because its
          # parent's +:replies+ was dropped.
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
          # Nested sub-filter at level 2: only the level-2 +Comment+
          # is restricted. Level-1 emits unfiltered (carries
          # +:replies+ with the level-2 array). Level-2 +c1.1+ emits
          # only +:body+ (drops +:id+ + +:replies+).
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
          # Folder-level +items+ sub-filter restricts each Item to
          # +:only [:id, :subfolder]+. The Item's +subfolder+
          # Association is kept; its inner Folder still emits
          # unfiltered (no +items+/+subfolder+ sub-Hash supplied at
          # depth 2 → +Filter::NONE+ propagates).
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
          # Three-level nested sub-filter — pins that the Filter
          # cell's child cache lifetime is one +serialize_*+ call
          # and that the cycle threads filter scopes correctly at
          # every hop. Level-3 Item is restricted to +:only [:id]+,
          # so +"deep-item"+ → +{"id":20}+.
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
end
