# typed: strict
# frozen_string_literal: true

module ActiveRecord
  module DynamicCredentials
    # +new_connection+ supplies the password for the first handshake. This
    # prepend covers a later handshake: a dead connection, or the lazy connect
    # that follows construction. A live session never enters +reconnect!+.
    #
    # The password is the cached one. A rejected attempt expires it and retries
    # once, so a rotation costs one extra fetch rather than a fetch per reconnect.
    #
    # Adapters disagree about which hash +connect+ reads. Postgres, Mysql2, and
    # SQLite use +@connection_parameters+. Trilogy uses +@config+. Both are
    # updated, then +super+ runs the adapter's own reconnect.
    module Reconnect
      #: (*untyped, **untyped) ?{ () -> void } -> void
      def reconnect!(*, **, &)
        apply_dynamic_credentials!
        begin
          super
        rescue StandardError => error
          refresh_and_retry(error) { super }
        end
      end

      private

      #: -> void
      def apply_dynamic_credentials!
        db_config = dynamic_db_config
        return unless db_config

        password = if db_config.respond_to?(:connection_password)
          db_config.connection_password
        elsif db_config.respond_to?(:current_password)
          db_config.current_password
        end
        return if password.blank?

        write_password(:@config, password)
        write_password(:@connection_parameters, password)
      end

      #: (Exception error) { () -> void } -> void
      def refresh_and_retry(error, &)
        @dynamic_credentials_refreshed ||= false #: bool?
        db_config = dynamic_db_config
        Kernel.raise error unless db_config.respond_to?(:refresh_after_rejection?) && db_config.refresh_after_rejection?(error)
        Kernel.raise error if @dynamic_credentials_refreshed

        @dynamic_credentials_refreshed = true
        db_config.expire_password!
        apply_dynamic_credentials!
        yield
      ensure
        @dynamic_credentials_refreshed = false
      end

      #: -> untyped
      def dynamic_db_config
        adapter = self #: as ActiveRecord::ConnectionAdapters::AbstractAdapter
        adapter.pool.db_config if adapter.pool.respond_to?(:db_config)
      end

      #: (Symbol ivar, String password) -> void
      def write_password(ivar, password)
        adapter = self #: as ActiveRecord::ConnectionAdapters::AbstractAdapter
        hash = adapter.instance_variable_get(ivar)
        return unless hash

        if hash.frozen?
          adapter.instance_variable_set(ivar, hash.merge(password: password))
        else
          hash[:password] = password
        end
      end
    end
  end
end
