# frozen_string_literal: true

module SerializersCodeGen
  class CodeBuilder
    INDENT_UNIT = "  "

    def initialize
      @lines = []
      @indent = 0
    end

    def line(str = "")
      @lines << (INDENT_UNIT * @indent) + str
    end

    def indent
      @indent += 1
      yield
    ensure
      @indent -= 1
    end

    def to_s
      @lines.join("\n")
    end
  end
end
