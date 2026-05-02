# frozen_string_literal: true

require "spec_helper"
require "serializers_code_gen"
require "shallow_generic"
require "shallow_specialized"
require "nested_composition"

# Cross-cutting +Filter+ contract — items (1)–(6) of the 10-item
# enumeration from +docs/testing.md § filter_spec.rb+. Items (7)–(10)
# (Source-keyed child filter, filter-before-+if:+ spy, +filters: nil+
# kwarg-omitted equivalence, full JSON/Hash parity) land in S14.4 once
# +filters.child(:<source>)+ scopes a real child cell against the
# nested Generated Class's +FIELD_INDEX+ (per
# +docs/research/filter_experiments_results.md § 1+).
#
# JSON/Hash parity is iterated at the describe block per
# +docs/testing.md § JSON/Hash parity+. Fixture strategy mirrors the
# guidance in +docs/testing.md § filter_spec.rb § Fixture strategy+:
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
#   carry the right shape (kept few — the corpus covers most stories).
#
# Per S14.3 acceptance: validation lives at +Filter.wrap+, runs once
# per +serialize_*+ call, and the emitted +_write_one+ / +_to_hash+
# bodies stay free of validation branches.
RSpec.describe "Filter — :only / :except / co-supplied / empty / unknown / no-inheritance" do
  def compile(fixture, mode)
    SerializersCodeGen.compile(fixture::DESCRIPTOR, output: mode, config: fixture::CONFIG)
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
          expect(SerializersCodeGen::Filter.wrap(nil)).to equal(SerializersCodeGen::Filter::NONE)
          expect(SerializersCodeGen::Filter.wrap({})).to equal(SerializersCodeGen::Filter::NONE)
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
end
