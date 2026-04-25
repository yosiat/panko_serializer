# frozen_string_literal: true

module SerializersCodeGen
  # Append-only buffer of indented Ruby source lines, used by the Generator
  # to produce a single string consumed identically by Compile (+module_eval+)
  # and Dump (+File.write+).
  class CodeBuilder
    # Indent unit prepended once per nesting level. Two spaces, matching
    # +standardrb+ defaults so generated source survives a lint pass unchanged.
    INDENT_UNIT = "  "

    # Returns a new builder with an empty buffer at indent level 0.
    #
    # @return [CodeBuilder]
    def initialize
      @lines = []
      @indent = 0
    end

    # Appends +str+ as a new line prefixed with the current indent.
    # Called with no argument (or +""+), emits a line containing only the
    # indent prefix — useful for visual spacing in the generated source.
    #
    # @param str [String] line content, without trailing newline or indent
    # @return [void]
    def line(str = "")
      @lines << (INDENT_UNIT * @indent) + str
    end

    # Raises the indent level by one for the duration of the block and
    # restores it on exit, including when the block raises.
    #
    # @yield runs the caller-supplied block at the increased indent level
    # @return [Object] the block's return value
    def indent
      @indent += 1
      yield
    ensure
      @indent -= 1
    end

    # Returns the buffered lines joined with +"\n"+. Idempotent — does not
    # mutate the buffer, so callers may keep appending after a +to_s+.
    #
    # @return [String] the assembled source
    def to_s
      @lines.join("\n")
    end
  end
end
