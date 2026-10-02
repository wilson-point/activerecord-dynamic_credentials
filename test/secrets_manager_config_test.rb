# frozen_string_literal: true

require "test_helper"
require "active_record/dynamic_credentials/secrets_manager"

class SecretsManagerConfigTest < Minitest::Test
  def setup
    @config = ActiveRecord::DynamicCredentials::SecretsManagerConfig.new(
      "production",
      "primary",
      {
        adapter: "postgresql",
        username: "obsidian",
        password: "fallback",
        host: "db.example",
        database: "obsidian_production",
        password_secret_arn: "arn:aws:secretsmanager:us-east-2:123:secret:rds"
      }
    )
  end

  def test_reads_password_from_rds_managed_json
    @config.secrets_manager_client = client('{"username":"obsidian","password":"rotated"}')

    assert_equal "rotated", @config.current_password
  end

  def test_accepts_a_raw_secret_string
    @config.secrets_manager_client = client("raw-password")

    assert_equal "raw-password", @config.current_password
  end

  def test_fetch_errors_return_nil_so_database_yml_can_stand
    @config.secrets_manager_client = Class.new do
      def get_secret_value(*)
        raise "access denied"
      end
    end.new

    _out, err = capture_io do
      assert_nil @config.current_password
    end
    assert_match "access denied", err
  end

  def test_missing_sdk_names_the_gem_to_add
    error = assert_raises(ActiveRecord::DynamicCredentials::Config::Error) do
      @config.send(:load_sdk!, "not-a-real-aws-sdk-#{Process.pid}")
    end
    assert_match "not-a-real-aws-sdk-#{Process.pid}", error.message
  end

  def test_config_reads_and_repeated_connections_fetch_the_secret_once
    calls = 0
    @config.secrets_manager_client = Class.new do
      define_method(:get_secret_value) do |*|
        calls += 1
        Struct.new(:secret_string).new('{"password":"rotated"}')
      end
    end.new
    @config.define_singleton_method(:adapter_class) { RecordingAdapter }

    5.times do
      @config.configuration_hash
      @config.host
      @config.database
      @config.adapter
    end
    assert_equal 0, calls

    3.times { @config.new_connection }

    adapter = Class.new do
      prepend ActiveRecord::DynamicCredentials::Reconnect

      attr_accessor :config, :connection_parameters, :pool

      def reconnect!(...)
      end
    end.new
    adapter.config = { password: "from-yml" }
    adapter.connection_parameters = { password: "from-yml" }
    adapter.pool = Struct.new(:db_config).new(@config)
    3.times { adapter.reconnect! }

    5.times { @config.configuration_hash }

    assert_equal 1, calls
  end

  def test_injected_client_is_reused_in_the_same_process
    @config.secrets_manager_client = :injected

    assert_equal :injected, @config.secrets_manager_client
    assert_equal :injected, @config.secrets_manager_client
  end

  def test_client_from_the_parent_process_is_dropped
    @config.instance_variable_set(:@secrets_manager_client, :parent)
    @config.instance_variable_set(:@secrets_manager_client_owner_pid, Process.pid + 1)

    error = assert_raises(ActiveRecord::DynamicCredentials::Config::Error) do
      @config.secrets_manager_client
    end

    assert_match "aws-sdk-secretsmanager", error.message
    assert_nil @config.instance_variable_get(:@secrets_manager_client)
  end

  def test_loading_a_config_does_not_build_a_client_or_fetch
    assert_nil @config.instance_variable_get(:@secrets_manager_client)
    assert_equal false, @config.instance_variable_get(:@password_fetched)

    @config.configuration_hash
    @config.host
    @config.database

    assert_nil @config.instance_variable_get(:@secrets_manager_client)
    assert_equal false, @config.instance_variable_get(:@password_fetched)
  end

  def test_handles_only_the_secrets_manager_kind
    klass = ActiveRecord::DynamicCredentials::SecretsManagerConfig
    assert_equal "secrets_manager", klass.kind
    assert_equal true, klass.handles?(dynamic_credential_kind: "secrets_manager")
    assert_equal true, klass.handles?(dynamic_credential_kind: :secrets_manager)
    assert_equal false, klass.handles?(dynamic_credential_kind: "")
    assert_equal false, klass.handles?(password_secret_arn: "arn:aws:secretsmanager:secret")
    assert_equal false, klass.handles?({})
  end

  class RecordingAdapter
    def initialize(config)
    end
  end

  private

  def client(secret_string)
    response = Struct.new(:secret_string).new(secret_string)
    Class.new do
      define_method(:get_secret_value) { |*| response }
    end.new
  end
end
