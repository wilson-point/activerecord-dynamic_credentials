# frozen_string_literal: true

require "test_helper"
require "active_record/dynamic_credentials/iam_auth"

class IamAuthConfigTest < Minitest::Test
  def test_generates_a_token_from_database_yml
    config = iam_config
    config.auth_token_generator = generator do |kwargs|
      assert_equal "us-east-2", kwargs[:region]
      assert_equal "db.example:5432", kwargs[:endpoint]
      assert_equal "app_iam", kwargs[:user_name]
      "iam-token"
    end

    assert_equal "iam-token", config.current_password
  end

  def test_region_falls_back_to_aws_region
    previous = ENV["AWS_REGION"]
    ENV["AWS_REGION"] = "us-west-2"
    config = iam_config(aws_region: nil)
    config.auth_token_generator = generator do |kwargs|
      assert_equal "us-west-2", kwargs[:region]
      "iam-token"
    end

    assert_equal "iam-token", config.current_password
  ensure
    ENV["AWS_REGION"] = previous
  end

  def test_missing_endpoint_fields_raise
    config = iam_config(port: nil)

    error = assert_raises(ActiveRecord::DynamicCredentials::Config::Error) do
      config.current_password
    end
    assert_match "port", error.message
  end

  def test_generator_from_the_parent_process_is_dropped
    config = iam_config
    config.instance_variable_set(:@auth_token_generator, :parent)
    config.instance_variable_set(:@auth_token_generator_owner_pid, Process.pid + 1)

    error = assert_raises(ActiveRecord::DynamicCredentials::Config::Error) do
      config.auth_token_generator
    end

    assert_match "aws-sdk-rds", error.message
    assert_nil config.instance_variable_get(:@auth_token_generator)
  end

  def test_token_is_reused_until_it_nears_expiry
    config = iam_config
    assert_equal 10 * 60, config.password_ttl
  end

  def test_register_rejects_a_block
    error = assert_raises(ActiveRecord::DynamicCredentials::Config::Error) do
      ActiveRecord::DynamicCredentials::IamAuthConfig.register! { true }
    end
    assert_match "does not take a block", error.message
  end

  private

  def iam_config(**overrides)
    attributes = {
      adapter: "postgresql",
      username: "app_iam",
      host: "db.example",
      port: 5432,
      database: "app",
      aws_region: "us-east-2"
    }.merge(overrides)
    attributes.delete(:aws_region) if overrides.key?(:aws_region) && overrides[:aws_region].nil?
    ActiveRecord::DynamicCredentials::IamAuthConfig.new("production", "primary", attributes)
  end

  def generator(&block)
    Class.new do
      define_method(:generate_auth_token) do |**kwargs|
        block.call(kwargs)
      end
    end.new
  end
end
