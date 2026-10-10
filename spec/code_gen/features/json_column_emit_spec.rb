# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "memory_profiler"

RSpec.describe "Specialized JSON-column emit path (S12.5)" do
  let(:descriptor) do
    Panko::CodeGen::Descriptor.new(
      name: "JsonColumnEmitSpecSerializer",
      model: PlainPost,
      parent_class: Fixtures::BaseSerializer,
      attributes: [
        Panko::CodeGen::Attribute.new(name: :id, source: :id),
        Panko::CodeGen::Attribute.new(name: :metadata, source: :metadata)
      ],
      method_attributes: [],
      associations: []
    )
  end

  def compile_for(mode)
    config = Panko::CodeGen::Config.new(json_column_emit: mode)
    Panko::CodeGen.compile(descriptor, output: :json, config: config).new(descriptor: descriptor)
  end

  describe "generated source - :wire_format" do
    it "contains push_json and Oj.sc_parse with the frozen strict-parse opts" do
      source = Panko::CodeGen::Generator.new.emit(
        descriptor,
        output: :json,
        config: Panko::CodeGen::Config.new(json_column_emit: :wire_format)
      )
      expect(source).to include('writer.push_json(raw, "metadata")')
      expect(source).to include("Oj.sc_parse(Panko::CodeGen::JSON_NOOP_PARSER, raw, Panko::CodeGen::JSON_STRICT_PARSE_OPTS)")
      expect(source).to include("rescue Oj::ParseError, EncodingError")
    end
  end

  describe "generated source - :html_safe" do
    it "contains push_value (today's shape) and does not contain push_json" do
      source = Panko::CodeGen::Generator.new.emit(
        descriptor,
        output: :json,
        config: Panko::CodeGen::Config.new(json_column_emit: :html_safe)
      )
      expect(source).to include('writer.push_value(record._read_attribute("metadata"), "metadata")')
      expect(source).not_to include("push_json")
      expect(source).not_to include("Oj.sc_parse")
    end
  end

  describe "happy path - saved record with valid JSON bytes" do
    it ":wire_format pushes the stored bytes verbatim through push_json" do
      PlainPost.create!(id: 1, metadata: {"a" => 1, "b" => "x"})
      record = PlainPost.find(1)

      output = compile_for(:wire_format).serialize_one(record)
      expect(output).to eq('{"id":1,"metadata":{"a":1,"b":"x"}}')
    end

    it ":html_safe takes the typecast Hash through push_value" do
      PlainPost.create!(id: 1, metadata: {"a" => 1, "b" => "x"})
      record = PlainPost.find(1)

      output = compile_for(:html_safe).serialize_one(record)
      expect(output).to eq('{"id":1,"metadata":{"a":1,"b":"x"}}')
    end
  end

  describe "aliased Attribute (#name differs from #source)" do
    let(:aliased_descriptor) do
      Panko::CodeGen::Descriptor.new(
        name: "AliasedJsonColumnSerializer",
        model: PlainPost,
        parent_class: Fixtures::BaseSerializer,
        attributes: [
          Panko::CodeGen::Attribute.new(name: :id, source: :id),
          Panko::CodeGen::Attribute.new(name: :extra, source: :metadata)
        ],
        method_attributes: [],
        associations: []
      )
    end

    def compile_aliased(mode)
      config = Panko::CodeGen::Config.new(json_column_emit: mode)
      Panko::CodeGen.compile(aliased_descriptor, output: :json, config: config).new(descriptor: aliased_descriptor)
    end

    it ":wire_format emits the alias name as the JSON key (saved record fast path)" do
      PlainPost.create!(id: 1, metadata: {"a" => 1})
      record = PlainPost.find(1)

      expect(compile_aliased(:wire_format).serialize_one(record))
        .to eq('{"id":1,"extra":{"a":1}}')
    end

    it ":wire_format emits the alias name as the JSON key (slow-path fallback on unsaved Hash)" do
      record = PlainPost.new(id: 1, metadata: {"a" => 1})

      expect(compile_aliased(:wire_format).serialize_one(record))
        .to eq('{"id":1,"extra":{"a":1}}')
    end

    it ":html_safe emits the alias name as the JSON key" do
      PlainPost.create!(id: 1, metadata: {"a" => 1})
      record = PlainPost.find(1)

      expect(compile_aliased(:html_safe).serialize_one(record))
        .to eq('{"id":1,"extra":{"a":1}}')
    end
  end

  describe "malformed JSON in DB" do
    # AR reads malformed JSON as +nil+; +Oj.sc_parse+ rejects the raw bytes, so the
    # fallback +push_value(_read_attribute(...))+ writes +null+.
    it ":wire_format falls through and emits null" do
      PlainPost.create!(id: 1, metadata: {"ok" => true})
      ::ActiveRecord::Base.connection.execute(
        "UPDATE posts SET metadata = '{not json' WHERE id = 1"
      )
      record = PlainPost.find(1)

      output = compile_for(:wire_format).serialize_one(record)
      expect(output).to eq('{"id":1,"metadata":null}')
    end
  end

  describe "in-memory unsaved Hash assignment" do
    it ":wire_format and :html_safe produce identical bytes" do
      record = PlainPost.new(id: 1, metadata: {"a" => 1})

      wire_format = compile_for(:wire_format).serialize_one(record)
      html_safe = compile_for(:html_safe).serialize_one(record)

      expect(wire_format).to eq(html_safe)
      expect(wire_format).to eq('{"id":1,"metadata":{"a":1}}')
    end
  end

  describe "in-place mutation (inherited-from-Panko stale-bytes behavior)" do
    # :wire_format reads +read_attribute_before_type_cast+, so it does not see an
    # unsaved in-place change; :html_safe reads +_read_attribute+ and does.
    it ":wire_format emits pre-mutation bytes; :html_safe emits post-mutation bytes" do
      PlainPost.create!(id: 1, metadata: {"a" => 1})
      record = PlainPost.find(1)
      record.metadata["new"] = "v"

      wire_format = compile_for(:wire_format).serialize_one(record)
      html_safe = compile_for(:html_safe).serialize_one(record)

      expect(wire_format).to eq('{"id":1,"metadata":{"a":1}}')
      expect(html_safe).to eq('{"id":1,"metadata":{"a":1,"new":"v"}}')
    end
  end

  describe "byte-divergence vs today's :html_safe (per phase_1_report 8.1)" do
    # Raw SQL, so the stored JSON bytes reach the column unchanged.

    def insert_metadata_bytes(id, raw_json)
      ::ActiveRecord::Base.connection.execute(
        "INSERT INTO posts (id, metadata) VALUES (#{id}, #{::ActiveRecord::Base.connection.quote(raw_json)})"
      )
    end

    it "</script> - :wire_format keeps raw bytes; :html_safe HTML-escapes" do
      insert_metadata_bytes(1, '{"html":"</script>"}')
      record = PlainPost.find(1)

      expect(compile_for(:wire_format).serialize_one(record))
        .to eq('{"id":1,"metadata":{"html":"</script>"}}')
      expect(compile_for(:html_safe).serialize_one(record))
        .to eq('{"id":1,"metadata":{"html":"\u003c/script\u003e"}}')
    end

    it "U+2028 line separator - :wire_format keeps raw codepoint; :html_safe escapes" do
      insert_metadata_bytes(1, "{\"sep\":\"a\u2028b\"}")
      record = PlainPost.find(1)

      expect(compile_for(:wire_format).serialize_one(record))
        .to eq("{\"id\":1,\"metadata\":{\"sep\":\"a\u2028b\"}}")
      expect(compile_for(:html_safe).serialize_one(record))
        .to eq('{"id":1,"metadata":{"sep":"a\u2028b"}}')
    end

    it "U+2029 paragraph separator - :wire_format keeps raw codepoint; :html_safe escapes" do
      insert_metadata_bytes(1, "{\"sep\":\"a\u2029b\"}")
      record = PlainPost.find(1)

      expect(compile_for(:wire_format).serialize_one(record))
        .to eq("{\"id\":1,\"metadata\":{\"sep\":\"a\u2029b\"}}")
      expect(compile_for(:html_safe).serialize_one(record))
        .to eq('{"id":1,"metadata":{"sep":"a\u2029b"}}')
    end

    it "-0.0 - :wire_format preserves the sign; :html_safe normalizes to 0.0" do
      insert_metadata_bytes(1, '{"v":-0.0}')
      record = PlainPost.find(1)

      expect(compile_for(:wire_format).serialize_one(record))
        .to eq('{"id":1,"metadata":{"v":-0.0}}')
      expect(compile_for(:html_safe).serialize_one(record))
        .to eq('{"id":1,"metadata":{"v":0.0}}')
    end

    it "scientific notation - :wire_format preserves compact form; :html_safe expands" do
      insert_metadata_bytes(1, '{"v":1e-300}')
      insert_metadata_bytes(2, '{"v":1e300}')
      records = PlainPost.order(:id).to_a

      wire_format = compile_for(:wire_format).serialize_many(records)
      expect(wire_format).to eq(
        '[{"id":1,"metadata":{"v":1e-300}},{"id":2,"metadata":{"v":1e300}}]'
      )

      html_safe = compile_for(:html_safe).serialize_many(records)
      expect(html_safe).to eq(
        '[{"id":1,"metadata":{"v":1.0e-300}},{"id":2,"metadata":{"v":1.0e+300}}]'
      )
    end
  end

  describe "allocation invariant (phase-1-bar carve-out)" do
    it ":wire_format total allocations ≤ :html_safe total allocations on saved records" do
      50.times do |i|
        PlainPost.create!(id: i + 1, metadata: {"category" => "tech", "tags" => %w[ruby json], "n" => i})
      end
      saved = PlainPost.order(:id).to_a

      wire_class = compile_for(:wire_format)
      html_class = compile_for(:html_safe)

      # Warm up first, so one-time first-call allocations do not count on either side.
      wire_class.serialize_many(saved)
      html_class.serialize_many(saved)

      wire_report = MemoryProfiler.report { wire_class.serialize_many(saved) }
      html_report = MemoryProfiler.report { html_class.serialize_many(saved) }

      expect(wire_report.total_allocated).to be <= html_report.total_allocated
    end
  end
end
