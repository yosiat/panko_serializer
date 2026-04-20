# frozen_string_literal: true

require "spec_helper"

# Coverage for the E6 direct +cached_writer+ dispatch in the unrolled
# non-indexed branch of +_write_ar_fallback+.
#
# After warmup, +attribute.cached_writer+ holds a type-specific writer
# (+StringWriter+, +IntegerWriter+, ...) resolved by +ValuesWriter::Writer#write+.
# E6 calls it directly — bypassing the static +ValuesWriter.write+ wrapper and
# its thread-local lookup — using a JSON key cached as +@_attr_#{i}_key+ at
# class build time.
#
# The +@_attr_#{i}_key+ cache raises a stability concern: if
# +attribute.name_for_serialization+ changed between class build time and
# call time, the cached key would be wrong. These specs pin down the cases
# where the concern could surface.
describe "E6 cached_writer direct dispatch in _write_ar_fallback" do
  describe "cold-to-hot transition" do
    before do
      Temping.create(:e6_transition_record) do
        with_columns do |t|
          t.string :title
          t.integer :count
        end
      end
    end

    class E6TransitionSerializer < Panko::Serializer
      attributes :title, :count
    end

    it "produces the same output on the first (cold) and second (hot) call" do
      record = E6TransitionRecord.new(title: "opus", count: 7)

      first = E6TransitionSerializer.new.serialize_to_json(record)
      second = E6TransitionSerializer.new.serialize_to_json(record)
      third = E6TransitionSerializer.new.serialize_to_json(record)

      parsed = Oj.load(first)
      expect(parsed).to eq("title" => "opus", "count" => 7)
      expect(second).to eq(first)
      expect(third).to eq(first)
    end

    it "populates cached_writer on the first call" do
      # Use a fresh serializer class so we start from a clean cached_writer
      # state and can observe the transition from nil to a concrete writer.
      fresh_cls = Class.new(Panko::Serializer) do
        attributes :title, :count
      end

      attrs_after_build = fresh_cls._descriptor.attributes
      expect(attrs_after_build.map(&:cached_writer)).to all(be_nil)

      record = E6TransitionRecord.new(title: "opus", count: 7)
      fresh_cls.new.serialize_to_json(record)

      # After one call the writer should have been resolved and stashed.
      expect(attrs_after_build[0].cached_writer).not_to be_nil
      expect(attrs_after_build[1].cached_writer).not_to be_nil
    end

    it "serializes nil values correctly on both cold and hot calls" do
      record = E6TransitionRecord.new(title: nil, count: nil)

      first = E6TransitionSerializer.new.serialize_to_json(record)
      second = E6TransitionSerializer.new.serialize_to_json(record)

      expect(Oj.load(first)).to eq("title" => nil, "count" => nil)
      expect(second).to eq(first)
    end
  end

  describe "attribute index / key stability across class pivot (STI)" do
    # A single serializer sees two different AR classes that share a table
    # (classic STI). +handle_class_change+ fires on every pivot and resets
    # cached_writer + type; the +@_attr_#{i}_key+ cached key must still
    # match the correct attribute slot.
    before do
      Temping.create(:e6_animal) do
        with_columns do |t|
          t.string :type
          t.string :nickname
          t.integer :age
        end
      end

      stub_const("E6Cat", Class.new(E6Animal))
      stub_const("E6Dog", Class.new(E6Animal))
    end

    class E6AnimalSerializer < Panko::Serializer
      attributes :nickname, :age
    end

    it "keeps keys aligned with values after Parent -> Child pivot" do
      cat = E6Cat.new(nickname: "whiskers", age: 3)
      dog = E6Dog.new(nickname: "rex", age: 9)
      animal = E6Animal.new(nickname: "generic", age: 1)

      # Alternate classes across iterations so +handle_class_change+ runs
      # on every call after the first.
      [animal, cat, dog, animal, cat, dog].each_with_index do |record, idx|
        json = E6AnimalSerializer.new.serialize_to_json(record)
        parsed = Oj.load(json)
        expect(parsed).to eq(
          "nickname" => record.nickname,
          "age" => record.age
        ), "iteration #{idx} with #{record.class} returned #{parsed.inspect}"
      end
    end

    it "keeps keys aligned with values after Child -> Parent pivot" do
      cat = E6Cat.new(nickname: "whiskers", age: 3)
      animal = E6Animal.new(nickname: "generic", age: 1)

      [cat, animal, cat, animal].each do |record|
        json = E6AnimalSerializer.new.serialize_to_json(record)
        parsed = Oj.load(json)
        expect(parsed["nickname"]).to eq(record.nickname)
        expect(parsed["age"]).to eq(record.age)
      end
    end
  end

  describe "AR +alias_attribute+ with class pivot" do
    # +handle_class_change+ rewrites +attr.name+ -> the underlying column
    # name (via +attribute_aliases+). The E6 fallback must still read the
    # right column AND emit the attribute under the DSL-declared name
    # (which +@_attr_#{i}_key+ caches at build time).
    before do
      Temping.create(:e6_real_named) do
        with_columns do |t|
          t.string :real_name
        end
        alias_attribute :nickname, :real_name
      end
      Temping.create(:e6_plain_named) do
        with_columns do |t|
          t.string :nickname
        end
      end
    end

    class E6NicknameSerializer < Panko::Serializer
      attributes :nickname
    end

    it "emits under the serializer's DSL name after pivoting into a class with alias_attribute" do
      plain = E6PlainNamed.new(nickname: "direct")
      aliased = E6RealNamed.new(real_name: "via-alias")

      # First pass: direct column access.
      json_plain = E6NicknameSerializer.new.serialize_to_json(plain)
      expect(Oj.load(json_plain)).to eq("nickname" => "direct")

      # Pivot to the aliased class — +handle_class_change+ rewrites
      # +attr.name+ to the underlying column, but the serialized key must
      # remain "nickname" (the DSL name). The cached +@_attr_i_key+ is
      # computed once at build time and must not drift.
      json_aliased = E6NicknameSerializer.new.serialize_to_json(aliased)
      expect(Oj.load(json_aliased)).to eq("nickname" => "via-alias")

      # Repeat on the aliased class — hot-path now has +cached_writer+
      # set; the serialized key must still be "nickname".
      aliased2 = E6RealNamed.new(real_name: "second")
      json_aliased_again = E6NicknameSerializer.new.serialize_to_json(aliased2)
      expect(Oj.load(json_aliased_again)).to eq("nickname" => "second")
    end
  end

  describe "partial select on non-indexed path" do
    before do
      Temping.create(:e6_merchant) do
        with_columns do |t|
          t.string :name
          t.string :address
          t.integer :merchant_id
        end
      end
    end

    class E6MerchantSerializer < Panko::Serializer
      attributes :name, :address, :merchant_id
    end

    it "emits nil for unselected columns while keeping keys correct", if: defined?(::ActiveRecord::Result::IndexedRow) do
      E6Merchant.create!(name: "opus", address: "addr", merchant_id: 42)
      record = E6Merchant.select(:id, :merchant_id).first
      # Force the non-indexed / dirty fallback branch by mutating the
      # record so +rs.has_attributes_hash+ flips to true.
      record.merchant_id = 99

      json = E6MerchantSerializer.new.serialize_to_json(record)
      parsed = Oj.load(json)
      expect(parsed).to eq(
        "name" => nil,
        "address" => nil,
        "merchant_id" => 99
      )
    end
  end

  describe "Panko DSL alias (attributes foo: :bar via +aliases+)" do
    before do
      Temping.create(:e6_aliased_record) do
        with_columns do |t|
          t.string :full_name
          t.integer :score
        end
      end
    end

    class E6DslAliasSerializer < Panko::Serializer
      attributes :score
      aliases full_name: :display_name
    end

    it "uses the DSL alias as the serialization key for unpersisted records" do
      record = E6AliasedRecord.new(full_name: "opus", score: 42)

      json = E6DslAliasSerializer.new.serialize_to_json(record)
      # First call (cold path) — still goes through ValuesWriter.write.
      expect(Oj.load(json)).to eq("display_name" => "opus", "score" => 42)
    end

    it "keeps the DSL alias after warmup (cached_writer populated, hot path)" do
      record = E6AliasedRecord.new(full_name: "opus", score: 42)

      E6DslAliasSerializer.new.serialize_to_json(record)
      # Second call — cached_writer should be populated and the E6 hot
      # path should fire with @_attr_i_key = "display_name".
      json = E6DslAliasSerializer.new.serialize_to_json(record)
      expect(Oj.load(json)).to eq("display_name" => "opus", "score" => 42)
    end
  end

  describe "cached_writer returning false falls back to type.deserialize" do
    # +DateTimeWriter#write+ returns false if +value+ is not a String. We
    # seed the cached_writer with a DateTimeWriter but hand it a DateTime
    # object so the E6 +|| push_value(type.deserialize(v), key)+ branch
    # fires. This mirrors the same fallback inside
    # +ValuesWriter::Writer#write+.
    before do
      Temping.create(:e6_event) do
        with_columns do |t|
          t.datetime :occurred_at
        end
      end
    end

    class E6EventSerializer < Panko::Serializer
      attributes :occurred_at
    end

    it "deserializes the value and writes the coerced form" do
      # Warmup with a persisted record so +occurred_at+ arrives as a
      # String (IndexedRow on Rails 8+); after that the attribute's
      # +cached_writer+ is a DateTimeWriter.
      warmup_time = Time.utc(2026, 4, 19, 12, 0, 0)
      E6Event.create!(occurred_at: warmup_time)

      persisted = E6Event.first
      E6EventSerializer.new.serialize_to_json(persisted)

      cw = E6EventSerializer._descriptor.attributes[0].cached_writer
      skip "DateTimeWriter not populated (driver returned non-string)" unless cw.is_a?(
        Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter::DateTimeWriter
      )

      # Now hand the fallback path a record where occurred_at is an
      # in-memory Time / ActiveSupport::TimeWithZone — DateTimeWriter
      # returns false for non-String values and E6 falls back to
      # +type.deserialize(v)+ + +push_value+.
      mutated = E6Event.first
      mutated.occurred_at = Time.utc(2026, 1, 1, 0, 0, 0)

      json = E6EventSerializer.new.serialize_to_json(mutated)
      parsed = Oj.load(json)
      expect(parsed).to have_key("occurred_at")
      # The deserialized form should round-trip back to 2026-01-01.
      expect(parsed["occurred_at"]).to include("2026-01-01")
    end
  end

  describe "ivar stamping" do
    before do
      Temping.create(:e6_stamp_record) do
        with_columns do |t|
          t.string :a
          t.string :b
          t.string :c
        end
      end
    end

    class E6StampSerializer < Panko::Serializer
      attributes :a, :b, :c
    end

    it "stamps per-attribute @_attr_i and @_attr_i_key ivars on the compiled class at build time" do
      compiled = E6StampSerializer._descriptor.engine_serializer

      [0, 1, 2].each do |i|
        attr_ivar = compiled.instance_variable_get(:"@_attr_#{i}")
        key_ivar = compiled.instance_variable_get(:"@_attr_#{i}_key")

        expect(attr_ivar).to be_a(Panko::Attribute)
        expect(attr_ivar).to equal(E6StampSerializer._descriptor.attributes[i])
        expect(key_ivar).to eq(attr_ivar.name_for_serialization)
      end
    end
  end
end
