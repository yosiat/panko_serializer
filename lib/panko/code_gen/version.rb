# frozen_string_literal: true

module Panko
  # Nested form on purpose: a standalone +require "panko/code_gen"+ loads this
  # file first, so it must define +Panko+ itself.
  module CodeGen
    VERSION = "0.1.0"

    # Shared by the generated file banner and the synthetic backtrace path.
    GENERATOR_NAME = "Panko::CodeGen"
  end
end
