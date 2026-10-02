# typed: strict

# The AWS SDK gems are optional. These shims cover the calls this gem makes
# after `load_sdk!` so those call sites can stay strict.
module Aws
  class CredentialProviderChain
    sig { void }
    def initialize; end

    sig { returns(T.untyped) }
    def resolve; end
  end

  module RDS
    class AuthTokenGenerator
      sig { params(credentials: T.untyped).void }
      def initialize(credentials:); end

      sig { params(region: String, endpoint: String, user_name: String).returns(String) }
      def generate_auth_token(region:, endpoint:, user_name:); end
    end
  end

  module SecretsManager
    class Client
      sig { params(options: T::Hash[Symbol, String]).void }
      def initialize(options = {}); end

      sig { params(secret_id: String).returns(SecretValue) }
      def get_secret_value(secret_id:); end
    end

    class SecretValue
      sig { returns(T.nilable(String)) }
      def secret_string; end
    end
  end
end
