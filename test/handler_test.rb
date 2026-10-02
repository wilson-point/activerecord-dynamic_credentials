# frozen_string_literal: true

require "test_helper"
require "active_record/dynamic_credentials/secrets_manager"
require "active_record/dynamic_credentials/iam_auth"

class HandlerTest < Minitest::Test
  def test_kind_selects_a_config_for_one_entry_and_leaves_the_other
    configs = configurations(
      "production" => {
        "primary" => {
          "adapter" => "postgresql",
          "database" => "obsidian_production",
          "username" => "obsidian",
          "password" => "fallback",
          "password_secret_arn" => "arn:aws:secretsmanager:us-east-2:123:secret:rds",
          "dynamic_credential_kind" => "secrets_manager"
        },
        "cache" => {
          "adapter" => "postgresql",
          "database" => "obsidian_cache",
          "password" => "static",
          "password_secret_arn" => "arn:aws:secretsmanager:us-east-2:123:secret:rds",
          "dynamic_credential_kind" => ""
        }
      }
    )

    primary = configs.configs_for(env_name: "production", name: "primary")
    cache = configs.configs_for(env_name: "production", name: "cache")

    assert_instance_of ActiveRecord::DynamicCredentials::SecretsManagerConfig, primary
    assert_nil primary.instance_variable_get(:@secrets_manager_client)
    assert_equal false, primary.instance_variable_get(:@password_fetched)
    assert_instance_of ActiveRecord::DatabaseConfigurations::HashConfig, cache
    assert_equal "static", cache.configuration_hash[:password]
  end

  def test_iam_kind_selects_iam_config_and_merges_a_url
    config = configurations(
      "production" => {
        "url" => "postgres://app_iam@db.example:5432/obsidian_production",
        "username" => "app_iam",
        "aws_region" => "us-east-2",
        "dynamic_credential_kind" => "iam_auth"
      }
    ).configs_for(env_name: "production", name: "primary")

    assert_instance_of ActiveRecord::DynamicCredentials::IamAuthConfig, config
    assert_equal "db.example", config.host
    assert_equal "app_iam", config.configuration_hash[:username]
    assert_equal 5432, config.configuration_hash[:port]
    assert_equal "obsidian_production", config.database
  end

  def test_unrelated_keys_stay_normal_configs
    hash_config = configurations(
      "development" => {
        "adapter" => "postgresql",
        "database" => "obsidian_development",
        "password" => "postgres"
      }
    ).configs_for(env_name: "development", name: "primary")

    url_config = configurations(
      "production" => {
        "url" => "postgres://obsidian:secret@db.example:5432/obsidian_production"
      }
    ).configs_for(env_name: "production", name: "primary")

    assert_instance_of ActiveRecord::DatabaseConfigurations::HashConfig, hash_config
    assert_equal "postgres", hash_config.configuration_hash[:password]
    assert_instance_of ActiveRecord::DatabaseConfigurations::UrlConfig, url_config
    assert_equal "secret", url_config.configuration_hash[:password]
  end

  def test_custom_kind_selects_that_class
    klass = Class.new(ActiveRecord::DynamicCredentials::Config) do
      kind :vault
    end
    klass.register!

    config = configurations(
      "production" => {
        "adapter" => "postgresql",
        "database" => "app",
        "dynamic_credential_kind" => "vault"
      }
    ).configs_for(env_name: "production", name: "primary")

    assert_instance_of klass, config
  end

  def test_register_requires_a_declared_kind
    klass = Class.new(ActiveRecord::DynamicCredentials::Config)
    error = assert_raises(ActiveRecord::DynamicCredentials::Config::Error) do
      klass.register!
    end
    assert_match "kind", error.message
  end

  def test_duplicate_kind_is_rejected
    Class.new(ActiveRecord::DynamicCredentials::Config) do
      kind :shared
    end.register!

    error = assert_raises(ActiveRecord::DynamicCredentials::Config::Error) do
      Class.new(ActiveRecord::DynamicCredentials::Config) do
        kind :shared
      end.register!
    end
    assert_match "shared", error.message
  end

  def test_prebuilts_stay_inactive_until_required
    code = <<~RUBY
      require "active_record/dynamic_credentials"
      config = ActiveRecord::DatabaseConfigurations.new(
        "production" => {
          "adapter" => "postgresql",
          "database" => "app",
          "password" => "static",
          "dynamic_credential_kind" => "secrets_manager"
        }
      ).configs_for(env_name: "production", name: "primary")
      abort config.class.name unless config.instance_of?(ActiveRecord::DatabaseConfigurations::HashConfig)
    RUBY

    output = IO.popen(["bundle", "exec", "ruby", "-e", code], err: [:child, :out], &:read)
    assert $?.success?, output
  end

  def test_register_is_idempotent
    before = ActiveRecord::DatabaseConfigurations.db_config_handlers.length
    ActiveRecord::DynamicCredentials::SecretsManagerConfig.register!
    ActiveRecord::DynamicCredentials::IamAuthConfig.register!
    assert_equal before, ActiveRecord::DatabaseConfigurations.db_config_handlers.length
  end

  def test_install_is_idempotent
    ancestors_before = ActiveRecord::ConnectionAdapters::AbstractAdapter.ancestors.count(ActiveRecord::DynamicCredentials::Reconnect)

    ActiveRecord::DynamicCredentials.install!

    ancestors_after = ActiveRecord::ConnectionAdapters::AbstractAdapter.ancestors.count(ActiveRecord::DynamicCredentials::Reconnect)
    assert_equal 1, ancestors_before
    assert_equal 1, ancestors_after
  end

  private

  def configurations(hash)
    ActiveRecord::DatabaseConfigurations.new(hash)
  end
end
