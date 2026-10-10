# frozen_string_literal: true

class DatabaseConfig
  ADAPTERS = {
    "sqlite" => {
      adapter: "sqlite3",
      database: ":memory:"
    }
  }.freeze

  def self.database_type
    ENV["DB"] || "sqlite"
  end

  def self.config
    adapter_config = ADAPTERS[database_type]
    raise "Unsupported database type: #{database_type}. Supported: #{ADAPTERS.keys.join(", ")}" unless adapter_config

    adapter_config
  end

  def self.setup_database
    # SQLite runs in memory, so there is nothing to create.
    puts "Using #{database_type} database: #{config[:database]}" if ENV["DEBUG"]
  end
end
