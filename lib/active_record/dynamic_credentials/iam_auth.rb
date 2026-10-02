# typed: strict
# frozen_string_literal: true

require_relative "config"

module ActiveRecord
  module DynamicCredentials
    # Selected by +dynamic_credential_kind: iam_auth+.
    # The auth token is the password and expires after 15 minutes.
    # Generation errors propagate.
    class IamAuthConfig < Config
      kind :iam_auth

      # @override
      #: -> String
      def current_password
        missing = []
        missing << "host" if configuration_hash[:host].blank?
        missing << "port" if configuration_hash[:port].blank?
        missing << "username" if configuration_hash[:username].blank?
        missing << "aws_region or AWS_REGION" if region.blank?
        unless missing.empty?
          raise Error, "RDS IAM auth requires #{missing.join(", ")} in the database config"
        end

        auth_region = region #: as String
        auth_token_generator.generate_auth_token(
          region: auth_region,
          endpoint: "#{configuration_hash[:host]}:#{configuration_hash[:port]}",
          user_name: configuration_hash[:username] #: as String
        )
      end

      #: -> Aws::RDS::AuthTokenGenerator
      def auth_token_generator
        fork_safe_client(:@auth_token_generator) do
          load_sdk!("aws-sdk-rds")
          Aws::RDS::AuthTokenGenerator.new(
            credentials: Aws::CredentialProviderChain.new.resolve
          )
        end
      end

      #: (Aws::RDS::AuthTokenGenerator auth_token_generator) -> void
      def auth_token_generator=(auth_token_generator)
        @auth_token_generator = auth_token_generator #: Aws::RDS::AuthTokenGenerator?
      end

      # Tokens expire after 15 minutes. Refresh before that so a new connection
      # does not present a dead token. Signing is local; this only limits how
      # often credentials are resolved.
      # @override
      #: -> Integer
      def password_ttl
        10 * 60
      end

      private

      #: -> String?
      def region
        configuration_hash[:aws_region].presence ||
          ENV["AWS_REGION"].presence ||
          ENV["AWS_DEFAULT_REGION"].presence
      end
    end

    IamAuthConfig.register!
  end
end
