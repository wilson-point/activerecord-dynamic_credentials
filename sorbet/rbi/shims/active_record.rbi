# typed: strict

# The generated Active Record RBIs reference Rails autoloads this bundle does
# not load. These are the methods the gem calls.

class Object
  sig { returns(T::Boolean) }
  def blank?; end

  sig { returns(T::Boolean) }
  def present?; end

  sig { returns(T.nilable(T.self_type)) }
  def presence; end
end

module ActiveRecord
  class Base
    sig { params(config: T.untyped).void }
    def self.configurations=(config); end
  end

  class ConnectionNotEstablished < StandardError; end
  class ConnectionTimeoutError < ConnectionNotEstablished; end
  class ConnectionNotDefined < ConnectionNotEstablished; end
  class NoDatabaseError < StandardError; end

  module ConnectionAdapters
    class AbstractAdapter
      sig { returns(T.untyped) }
      def pool; end

      sig { params(restore_transactions: T::Boolean).void }
      def reconnect!(restore_transactions: false); end
    end
  end

  class DatabaseConfigurations
    class ConnectionUrlResolver
      sig { params(url: String).void }
      def initialize(url); end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_hash; end
    end

    class DatabaseConfig
      sig { returns(T.untyped) }
      def adapter_class; end

      sig { returns(T.untyped) }
      def new_connection; end
    end

    class HashConfig < DatabaseConfig
      sig { params(env_name: String, name: String, configuration_hash: T::Hash[Symbol, T.untyped]).void }
      def initialize(env_name, name, configuration_hash); end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def configuration_hash; end
    end

    sig do
      params(
        blk: T.proc.params(
          env_name: String,
          name: String,
          url: T.nilable(String),
          config: T::Hash[Symbol, T.untyped]
        ).returns(T.untyped)
      ).void
    end
    def self.register_db_config_handler(&blk); end
  end
end
