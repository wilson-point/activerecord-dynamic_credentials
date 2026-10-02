# frozen_string_literal: true

require "test_helper"

class ReconnectTest < Minitest::Test
  class FakeAdapter
    prepend ActiveRecord::DynamicCredentials::Reconnect

    attr_accessor :config, :connection_parameters, :pool, :fail_with
    attr_reader :super_config_password, :super_connection_password, :super_calls

    def initialize
      @super_calls = 0
    end

    def reconnect!(...)
      @super_calls += 1
      if @fail_with
        error = @fail_with
        @fail_with = nil
        raise error
      end
      @super_config_password = config[:password]
      @super_connection_password = connection_parameters&.[](:password)
    end
  end

  class RecordingAdapter
    attr_reader :config

    def initialize(config)
      @config = config
    end
  end

  def setup
    @adapter = FakeAdapter.new
    @adapter.config = { username: "obsidian", password: "stale" }
    @adapter.connection_parameters = { user: "obsidian", password: "stale", dbname: "obsidian_production" }
  end

  def test_reconnect_writes_current_password_before_super
    @adapter.pool = pool_with("rotated")

    @adapter.reconnect!

    assert_equal "rotated", @adapter.super_config_password
    assert_equal "rotated", @adapter.super_connection_password
    assert_equal 1, @adapter.super_calls
  end

  def test_nil_password_keeps_the_database_yml_password
    @adapter.pool = pool_with(nil)

    @adapter.reconnect!

    assert_equal "stale", @adapter.super_config_password
    assert_equal "stale", @adapter.super_connection_password
  end

  def test_configs_without_current_password_are_left_alone
    @adapter.pool = Struct.new(:db_config).new(Object.new)

    @adapter.reconnect!

    assert_equal "stale", @adapter.super_config_password
  end

  def test_frozen_config_is_replaced_instead_of_mutated
    @adapter.config = { username: "obsidian", password: "stale" }.freeze
    @adapter.connection_parameters = { password: "stale" }.freeze
    @adapter.pool = pool_with("rotated")

    @adapter.reconnect!

    assert_equal "rotated", @adapter.config[:password]
    assert_equal "rotated", @adapter.connection_parameters[:password]
    assert_equal false, @adapter.config.frozen?
  end

  def test_missing_connection_parameters_still_updates_config
    @adapter.connection_parameters = nil
    @adapter.pool = pool_with("rotated")

    @adapter.reconnect!

    assert_equal "rotated", @adapter.super_config_password
    assert_nil @adapter.super_connection_password
  end

  def test_new_connection_embeds_the_password_and_reuses_it
    calls = 0
    config = password_config { calls += 1; "rotated" }
    config.define_singleton_method(:adapter_class) { RecordingAdapter }

    first = config.new_connection
    second = config.new_connection
    @adapter.pool = Struct.new(:db_config).new(config)
    @adapter.reconnect!

    assert_equal "rotated", first.config[:password]
    assert_equal "rotated", second.config[:password]
    assert_equal "rotated", @adapter.super_config_password
    assert_equal 1, calls
  end

  def test_first_connection_retries_when_the_password_is_rejected
    calls = 0
    passwords = ["stale-secret", "rotated"]
    attempts = 0
    config = password_config { calls += 1; passwords.shift }
    adapter = Class.new do
      attr_reader :config

      define_method(:initialize) do |hash|
        attempts += 1
        @config = hash
        raise ActiveRecord::NoDatabaseError, "Database not found: app" if attempts == 1
      end
    end
    config.define_singleton_method(:adapter_class) { adapter }

    connection = config.new_connection

    assert_equal "rotated", connection.config[:password]
    assert_equal 2, calls
  end

  def test_concurrent_new_connections_each_retry_a_rejected_password
    calls = 0
    config = password_config do
      calls += 1
      calls == 1 ? "stale" : "rotated-#{calls}"
    end
    entered = Queue.new
    hold = Queue.new
    adapter = Class.new do
      attr_reader :config

      define_method(:initialize) do |hash|
        @config = hash
        next unless hash[:password] == "stale"

        entered << true
        hold.pop
        raise ActiveRecord::NoDatabaseError, "Database not found: app"
      end
    end
    config.define_singleton_method(:adapter_class) { adapter }

    threads = Array.new(2) { Thread.new { config.new_connection } }
    2.times { entered.pop }
    2.times { hold << true }
    connections = threads.map(&:value)

    assert_equal ["rotated-2", "rotated-3"].sort, connections.map { |connection| connection.config[:password] }.sort
  end

  def test_rejected_password_is_fetched_again
    calls = 0
    passwords = ["stale-secret", "rotated"]
    config = password_config { calls += 1; passwords.shift }
    @adapter.pool = Struct.new(:db_config).new(config)
    @adapter.fail_with = ActiveRecord::NoDatabaseError.new("Database not found: app")

    @adapter.reconnect!

    assert_equal "rotated", @adapter.super_config_password
    assert_equal 2, calls
    assert_equal 2, @adapter.super_calls
  end

  def test_hostname_failure_does_not_fetch_again
    calls = 0
    config = password_config { calls += 1; "rotated" }
    @adapter.pool = Struct.new(:db_config).new(config)
    @adapter.fail_with = ActiveRecord::DatabaseConnectionError.hostname_error("db.example")

    assert_raises(ActiveRecord::DatabaseConnectionError) { @adapter.reconnect! }
    assert_equal 1, calls
    assert_equal 1, @adapter.super_calls
  end

  def test_expired_password_is_fetched_again
    calls = 0
    config = password_config { calls += 1; "token-#{calls}" }
    config.define_singleton_method(:password_ttl) { 0 }

    assert_equal "token-1", config.connection_password
    assert_equal "token-2", config.connection_password
    assert_equal 2, calls
  end

  def test_custom_scheme_is_applied_without_a_builtin_handler
    config = Class.new(ActiveRecord::DynamicCredentials::Config) do
      def current_password
        "vault-token"
      end
    end.new("production", "primary", { adapter: "mysql2", host: "db" })
    @adapter.pool = Struct.new(:db_config).new(config)

    @adapter.reconnect!

    assert_equal "vault-token", @adapter.super_config_password
    assert_equal "vault-token", @adapter.super_connection_password
  end

  private

  def password_config(&block)
    Class.new(ActiveRecord::DynamicCredentials::Config) do
      define_method(:current_password, &block)
    end.new("production", "primary", { adapter: "postgresql", password: "from-yml" })
  end

  def pool_with(password)
    db_config = Object.new
    db_config.define_singleton_method(:current_password) { password }
    Struct.new(:db_config).new(db_config)
  end
end
