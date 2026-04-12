# frozen_string_literal: true

module Panko
  module CodeGen
    # Source string builder for generated serializer methods.
    #
    # Provides methods for each per-attribute code pattern. The {Compiler}
    # creates an Emitter, calls pattern methods for each attribute, and
    # retrieves the assembled source via {#to_source}.
    #
    # Never called at runtime — only during class compilation.
    class Emitter
      def initialize
        @lines = []
      end

      # Appends a raw source line.
      #
      # @param line [String] a line of Ruby source
      # @return [void]
      def <<(line)
        @lines << line
      end

      # Returns the assembled Ruby source string.
      #
      # @return [String]
      def to_source
        @lines.join("\n")
      end

      # --- Indexed cached hot path (post-warmup) ---

      # Emits one unrolled attribute read + write from the parallel caches.
      # Three-branch dispatch: direct push_value, nil, or writer.write.
      #
      # @param i [Integer] attribute index in the parallel cache arrays
      # @return [void]
      def emit_cached_attr(i)
        self << "v = row[aw.col[#{i}]]"
        self << "if aw.dir[#{i}]"
        self << "  writer.push_value(v, aw.key[#{i}])"
        self << "elsif v.nil?"
        self << "  writer.push_value(nil, aw.key[#{i}])"
        self << "else"
        self << "  aw.wtr[#{i}].write(v, writer, aw.key[#{i}])"
        self << "end"
      end

      # Emits one guarded attribute for the filtered cached path.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_cached_attr_filtered(i)
        self << "if attr_mask[#{i}]"
        self << "  v = row[aw.col[#{i}]]"
        self << "  if aw.dir[#{i}]"
        self << "    writer.push_value(v, aw.key[#{i}])"
        self << "  elsif v.nil?"
        self << "    writer.push_value(nil, aw.key[#{i}])"
        self << "  else"
        self << "    aw.wtr[#{i}].write(v, writer, aw.key[#{i}])"
        self << "  end"
        self << "end"
      end

      # --- Indexed first pass (type resolution, runs once) ---

      # Emits one unrolled attribute for the first-pass type resolution path.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_first_pass_attr(i)
        self << "attr = attrs[#{i}]"
        self << "ci_val = ci[attr.name]"
        self << "v = ci_val ? row[ci_val] : nil"
        self << "_resolve_type(attr, rs) if attr.type.nil? && v"
        self << "_write_value(attr, v, writer)"
      end

      # Emits one guarded attribute for the filtered first-pass path.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_first_pass_attr_filtered(i)
        self << "if attr_mask[#{i}]"
        self << "  attr = attrs[#{i}]"
        self << "  ci_val = ci[attr.name]"
        self << "  v = ci_val ? row[ci_val] : nil"
        self << "  _resolve_type(attr, rs) if attr.type.nil? && v"
        self << "  _write_value(attr, v, writer)"
        self << "else"
        self << "  attr = attrs[#{i}]"
        self << "  ci_val = ci[attr.name]"
        self << "  v = ci_val ? row[ci_val] : nil"
        self << "  _resolve_type(attr, rs) if attr.type.nil? && v"
        self << "end"
      end

      # --- Indexed with dirty attributes fallback ---

      # Emits one unrolled attribute for the indexed-with-dirty-hash path.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_indexed_with_hash_attr(i)
        self << "attr = attrs[#{i}]"
        self << "v = nil"
        self << "am = ah[attr.name]"
        self << "if am"
        self << "  v = am.instance_variable_get(:@value_before_type_cast)"
        self << "  attr.type ||= am.instance_variable_get(:@type)"
        self << "end"
        self << "if v.nil?"
        self << "  ci_val = ci[attr.name]"
        self << "  v = row[ci_val] if ci_val"
        self << "end"
        self << "_resolve_type(attr, rs) if attr.type.nil? && v"
        self << "_write_value(attr, v, writer)"
      end

      # Emits one guarded attribute for the filtered indexed-with-hash path.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_indexed_with_hash_attr_filtered(i)
        self << "if attr_mask[#{i}]"
        self << "  attr = attrs[#{i}]"
        self << "  v = nil"
        self << "  am = ah[attr.name]"
        self << "  if am"
        self << "    v = am.instance_variable_get(:@value_before_type_cast)"
        self << "    attr.type ||= am.instance_variable_get(:@type)"
        self << "  end"
        self << "  if v.nil?"
        self << "    ci_val = ci[attr.name]"
        self << "    v = row[ci_val] if ci_val"
        self << "  end"
        self << "  _resolve_type(attr, rs) if attr.type.nil? && v"
        self << "  _write_value(attr, v, writer)"
        self << "end"
      end

      # --- Non-indexed fallback (Rails 7.x) ---

      # Emits one unrolled attribute for the non-indexed path.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_non_indexed_attr(i)
        self << "v = rs.read_attribute(attrs[#{i}])"
        self << "Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, attrs[#{i}], v)"
      end

      # Emits one guarded attribute for the filtered non-indexed path.
      #
      # @param i [Integer] attribute index
      # @return [void]
      def emit_non_indexed_attr_filtered(i)
        self << "if attr_mask[#{i}]"
        self << "  v = rs.read_attribute(attrs[#{i}])"
        self << "  Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, attrs[#{i}], v)"
        self << "end"
      end
    end
  end
end
