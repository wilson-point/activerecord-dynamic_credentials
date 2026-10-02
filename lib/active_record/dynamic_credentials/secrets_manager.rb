# typed: strict
# frozen_string_literal: true

require "json"
require_relative "config"

module ActiveRecord
  module DynamicCredentials
    # Selected by +dynamic_credential_kind: secrets_manager+.
    # The secret is RDS-managed JSON (`{"password":"..."}`) or a raw password.
    # A fetch failure leaves the database.yml password in place.
    class SecretsManagerConfig < Config
      kind :secrets_manager

      # @override
      #: -> String?
      def current_password
        password_from_secret(
          secrets_manager_client.get_secret_value(secret_id: secret_arn).secret_string #: as String
        )
      rescue Error
        raise
      rescue StandardError => error
        log_fetch_error(error)
        nil
      end

      #: -> Aws::SecretsManager::Client
      def secrets_manager_client
        fork_safe_client(:@secrets_manager_client) do
          load_sdk!("aws-sdk-secretsmanager")
          Aws::SecretsManager::Client.new(client_options)
        end
      end

      #: (Aws::SecretsManager::Client secrets_manager_client) -> void
      def secrets_manager_client=(secrets_manager_client)
        @secrets_manager_client = secrets_manager_client #: Aws::SecretsManager::Client?
      end

      private

      #: -> String
      def secret_arn
        configuration_hash[:password_secret_arn]
      end

      #: -> Hash[Symbol, String]
      def client_options
        region = configuration_hash[:aws_region]
        region.present? ? { region: region } : {}
      end

      #: (String secret_string) -> String
      def password_from_secret(secret_string)
        JSON.parse(secret_string).fetch("password")
      rescue JSON::ParserError
        secret_string
      end

      #: (Exception error) -> void
      def log_fetch_error(error)
        message = "Error fetching AWS Secrets Manager password: #{error.message}"
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.error(message)
        else
          warn(message)
        end
      end
    end

    SecretsManagerConfig.register!
  end
end
