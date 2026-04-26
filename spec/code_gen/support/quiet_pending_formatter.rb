require "rspec/core/formatters/progress_formatter"

# Progress formatter variant that drops the "Pending:" detail block
# while leaving the trailing summary line ("N examples, M failures,
# K pending") intact. The pending count is the load-bearing signal for
# slice-boundary verification; the per-example pending bodies are noise
# in automated implementer logs.
#
# Registered via `--format QuietPendingFormatter` in `.rspec`.
class QuietPendingFormatter < RSpec::Core::Formatters::ProgressFormatter
  RSpec::Core::Formatters.register self, :dump_pending

  # Suppresses the "Pending:" section. The summary line is emitted
  # separately by +dump_summary+ on the parent and remains untouched.
  #
  # @param _notification [RSpec::Core::Notifications::ExamplesNotification]
  # @return [void]
  def dump_pending(_notification)
  end
end
