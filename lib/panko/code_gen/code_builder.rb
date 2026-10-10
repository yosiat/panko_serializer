# frozen_string_literal: true

module Panko::CodeGen
  class CodeBuilder
    INDENT_UNIT = "  "

    def initialize
      @lines = []
      @indent = 0
    end

    def line(str = "")
      @lines << (INDENT_UNIT * @indent) + str
    end

    # Unlike +line("")+, adds no indent, so the output has no trailing whitespace.
    def blank
      @lines << ""
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
