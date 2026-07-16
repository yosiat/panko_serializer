# frozen_string_literal: true

require_relative "benchmark"

# Target-callable registry — one Hash per target family, keyed by scenario
# symbol, valued by lambdas that take +records+ and return the serialized
# output. Scenario files populate the entries they need (per
# docs/code_gen/benchmarks.md § Scenario file shape) and then read them back from
# their `benchmark_scenario` block.
#
# Adding a new target family means adding one Hash here. Adding a new scenario
# means adding one entry per relevant family from the scenario file. Never
# both, never N-way (per docs/code_gen/benchmarks.md § Why scenario-centric).
module Targets
  CODE_GEN_JSON = {}
  CODE_GEN_HASH = {}
  PANKO_JSON = {}
  PANKO_OBJECT = {}
  OJ_JSON = {}
  PLAIN_JSON = {}
  PLAIN_HASH = {}
end
