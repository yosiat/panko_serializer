# frozen_string_literal: true

# Database configuration helper for tests
class DatabaseConfig
  ADAPTERS = {
    "sqlite" => {
      adapter: "sqlite3",
      database: ":memory:"
    },
    "postgresql" => {
      adapter: "postgresql",
      database: "panko_test",
      host: ENV["POSTGRES_HOST"] || "localhost",
      username: ENV["POSTGRES_USER"] || "postgres",
      password: ENV["POSTGRES_PASSWORD"] || "",
      port: ENV["POSTGRES_PORT"] || 5432
    },
    "mysql" => {
      adapter: "trilogy",
      database: "panko_test",
      host: ENV["MYSQL_HOST"] || "localhost",
      username: ENV["MYSQL_USER"] || "root",
      password: ENV["MYSQL_PASSWORD"] || "",
      port: ENV["MYSQL_PORT"] || 3306
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
    # For CI and local development, we assume databases are already created
    # SQLite uses in-memory database which needs no setup
    # PostgreSQL and MySQL databases should be created externally
    puts "Using #{database_type} database: #{config[:database]}" if ENV["DEBUG"]
  end

  def self.teardown_database
    # For SQLite in-memory, no teardown needed
    # For persistent databases, we rely on test transaction rollbacks
    # rather than dropping/recreating the database for performance
  end
end
