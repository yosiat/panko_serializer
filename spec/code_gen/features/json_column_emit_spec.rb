# frozen_string_literal: true

require "spec_helper"
require "panko/code_gen"
require "memory_profiler"

# End-to-end behavior + regression spec for the S12.5 JSON-column emit path
# on the Specialized record-access path. Covers the five rows from
# +docs/research/phase_1_report.md § 8.1+'s Panko-parity table plus the
# byte-divergence rows that distinguish +:wire_format+ from today's
# +push_value(Hash)+ shape:
#
# - happy path: a Specialized Descriptor on +PlainPost+ emits via
#   +push_json+; the generated source contains +push_json+ and
#   +Oj.sc_parse+ with +mode: :strict+;
# - mode-selection: with +Config#json_column_emit: :html_safe+ the
#   generated source contains +push_value+ (today's shape) and not
#   +push_json+;
# - allocation invariant: pinned via +MemoryProfiler+ in-spec —
#   +:wire_format+ allocates no more than today's +:html_safe+ shape on
#   a saved-record fixture (the carve-out clause from
#   +docs/phase-1-bar.md § json_column allocation carve-out+);
# - malformed JSON in DB: raw bytes that +Oj.sc_parse+ rejects → emit
#   falls through, produces +null+;
# - in-memory unsaved Hash assignment: +record.metadata = {...}+ (no
#   save) → falls through, byte-identical to +:html_safe+;
# - in-place mutation: documented and pinned as inherited-from-Panko
#   stale-bytes behavior;
# - byte-divergence vs today's scg: +</script>+, U+2028, U+2029, +-0.0+,
#   +1e-300+, +1e300+ produce the bytes recorded in this spec — the
#   regression contract for the +:wire_format+ default that S12.5
#   inherited from Panko 0.8.5.
RSpec.describe "Specialized JSON-column emit path (S12.5)" do
  let(:descriptor) do
    Panko::CodeGen::Descriptor.new(
      name: "JsonColumnEmitSpecSerializer",
      models: [PlainPost],
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

  describe "generated source — :wire_format" do
    it "contains push_json and Oj.sc_parse with mode: :strict" do
      source = Panko::CodeGen::Generator.new.emit(
        descriptor,
        output: :json,
        config: Panko::CodeGen::Config.new(json_column_emit: :wire_format)
      )
      expect(source).to include('writer.push_json(raw, "metadata")')
      expect(source).to include("Oj.sc_parse(Panko::CodeGen::JSON_NOOP_PARSER, raw, mode: :strict)")
      expect(source).to include("rescue Oj::ParseError, EncodingError")
    end
  end

  describe "generated source — :html_safe" do
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

  describe "happy path — saved record with valid JSON bytes" do
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
    # Pin that the OUTPUT JSON key is +Attribute#name+ while the column
    # read uses +Attribute#source+ — same contract as +emit_json+ on
    # non-JSON-column Attributes. Both modes must agree on the key
    # because a Descriptor's user-facing key is +name+, not +source+.
    let(:aliased_descriptor) do
      Panko::CodeGen::Descriptor.new(
        name: "AliasedJsonColumnSerializer",
        models: [PlainPost],
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
    # AR's typecast-on-read returns +nil+ for malformed JSON bytes (the
    # column type's +deserialize+ rescues the parse error internally).
    # +:wire_format+'s +Oj.sc_parse+ guard rejects the raw bytes; emit
    # falls through to +push_value(_read_attribute(...))+ which sees
    # +nil+ and writes +null+.
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
    # Inherited contract: callers that mutate the typecast Hash without
    # +save+ / +metadata_will_change!+ get the pre-mutation bytes
    # because the +:wire_format+ path reads
    # +read_attribute_before_type_cast+ — the original String, before AR
    # built the typecast Hash. Today's +:html_safe+ path reads
    # +_read_attribute+ and observes the mutation. Pinned so a future
    # adapter-driven typecast change surfaces as a test failure.
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

  describe "byte-divergence vs today's :html_safe (per phase_1_report § 8.1)" do
    # Each row inserts pre-encoded JSON bytes via raw SQL so the bytes
    # hit the column unmodified; the read-side path is then exercised
    # against both modes. These rows codify the byte-divergence contract
    # +:wire_format+ inherited from Panko 0.8.5 — every cell here is the
    # bytes Panko emits today.

    def insert_metadata_bytes(id, raw_json)
      ::ActiveRecord::Base.connection.execute(
        "INSERT INTO posts (id, metadata) VALUES (#{id}, #{::ActiveRecord::Base.connection.quote(raw_json)})"
      )
    end

    it "</script> — :wire_format keeps raw bytes; :html_safe HTML-escapes" do
      insert_metadata_bytes(1, '{"html":"</script>"}')
      record = PlainPost.find(1)

      expect(compile_for(:wire_format).serialize_one(record))
        .to eq('{"id":1,"metadata":{"html":"</script>"}}')
      # Today's emit goes through +Hash#as_json+ + Oj +:rails+ mode, which
      # escapes +<+ / +>+ to their +\\u003c+ / +\\u003e+ JSON-escape
      # forms. The stored bytes contain the raw +</script>+, so this is
      # +:html_safe+ adding escape on the read path.
      expect(compile_for(:html_safe).serialize_one(record))
        .to eq('{"id":1,"metadata":{"html":"\u003c/script\u003e"}}')
    end

    it "U+2028 line separator — :wire_format keeps raw codepoint; :html_safe escapes" do
      insert_metadata_bytes(1, "{\"sep\":\"a\u2028b\"}")
      record = PlainPost.find(1)

      expect(compile_for(:wire_format).serialize_one(record))
        .to eq("{\"id\":1,\"metadata\":{\"sep\":\"a\u2028b\"}}")
      # +Hash#as_json+ + Oj +:rails+ mode escape U+2028 to its +\u2028+ JSON
      # escape sequence on the read path; the stored bytes contain the raw
      # codepoint, so this is +:html_safe+ adding escape on emit.
      expect(compile_for(:html_safe).serialize_one(record))
        .to eq('{"id":1,"metadata":{"sep":"a\u2028b"}}')
    end

    it "U+2029 paragraph separator — :wire_format keeps raw codepoint; :html_safe escapes" do
      insert_metadata_bytes(1, "{\"sep\":\"a\u2029b\"}")
      record = PlainPost.find(1)

      expect(compile_for(:wire_format).serialize_one(record))
        .to eq("{\"id\":1,\"metadata\":{\"sep\":\"a\u2029b\"}}")
      expect(compile_for(:html_safe).serialize_one(record))
        .to eq('{"id":1,"metadata":{"sep":"a\u2029b"}}')
    end

    it "-0.0 — :wire_format preserves the sign; :html_safe normalizes to 0.0" do
      insert_metadata_bytes(1, '{"v":-0.0}')
      record = PlainPost.find(1)

      expect(compile_for(:wire_format).serialize_one(record))
        .to eq('{"id":1,"metadata":{"v":-0.0}}')
      expect(compile_for(:html_safe).serialize_one(record))
        .to eq('{"id":1,"metadata":{"v":0.0}}')
    end

    it "scientific notation — :wire_format preserves compact form; :html_safe expands" do
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
    # Pin the carve-out clause from +docs/phase-1-bar.md+: +:wire_format+
    # allocates no more than today's +:html_safe+ shape on the same
    # records. The bench numbers in +phase_1_report.md § 3.1.6+ are the
    # canonical macro signal; this in-spec assertion is the focused
    # regression spec a future codegen drift would trip first.
    it ":wire_format total allocations ≤ :html_safe total allocations on saved records" do
      50.times do |i|
        PlainPost.create!(id: i + 1, metadata: {"category" => "tech", "tags" => %w[ruby json], "n" => i})
      end
      saved = PlainPost.order(:id).to_a

      wire_class = compile_for(:wire_format)
      html_class = compile_for(:html_safe)

      # Warmup so JIT / lazy AR caches don't pollute either side.
      wire_class.serialize_many(saved)
      html_class.serialize_many(saved)

      wire_report = MemoryProfiler.report { wire_class.serialize_many(saved) }
      html_report = MemoryProfiler.report { html_class.serialize_many(saved) }

      expect(wire_report.total_allocated).to be <= html_report.total_allocated
    end
  end
end
