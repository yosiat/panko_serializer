# frozen_string_literal: true

module Panko
  module CodeGen
    class Emitter
      # AR attribute emit methods — indexed cached, first-pass, dirty fallback,
      # and non-indexed paths. Both JSON (writer) and Hash (result) variants.
      module ActiveRecordAttributes
        # --- Indexed cached hot path (post-warmup) ---

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

        def emit_first_pass_attr(i)
          self << "attr = attrs[#{i}]"
          self << "ci_val = ci[attr.name]"
          self << "v = ci_val ? row[ci_val] : nil"
          self << "_resolve_type(attr, rs) if attr.type.nil? && v"
          self << "_write_value(attr, v, writer)"
        end

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

        def emit_non_indexed_attr(i)
          self << "v = rs.read_attribute(attrs[#{i}])"
          self << "Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, attrs[#{i}], v)"
        end

        def emit_non_indexed_attr_filtered(i)
          self << "if attr_mask[#{i}]"
          self << "  v = rs.read_attribute(attrs[#{i}])"
          self << "  Panko::Engine::AttributesWriter::ActiveRecord::ValuesWriter.write(writer, attrs[#{i}], v)"
          self << "end"
        end
      end
    end
  end
end
