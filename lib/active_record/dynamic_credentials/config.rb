# typed: strict
# frozen_string_literal: true

require "active_record/database_configurations"

module ActiveRecord
  module DynamicCredentials
    #: type db_config = Hash[Symbol, untyped]

    # Subclass, declare +kind+, implement +current_password+, then +register!+.
    # Entries whose +dynamic_credential_kind+ matches use this class. A blank
    # or missing +dynamic_credential_kind+ stays a normal Rails config.
    # Return nil from +current_password+ to keep the database.yml password.
    class Config < ActiveRecord::DatabaseConfigurations::HashConfig
      class Error < StandardError; end

      KIND_REGISTRY = {} #: Hash[String, untyped]
      private_constant :KIND_REGISTRY

      #: (?String | Symbol | nil value) -> String?
      def self.kind(value = nil)
        if value
          @kind = value.to_s #: String?
        end
        @kind
      end

      #: ?{ () -> void } -> void
      def self.register!(&block)
        raise Error, "#{self}.register! does not take a block; set dynamic_credential_kind in database.yml" if block

        declared = kind
        raise Error, "#{self} must declare a kind" if declared.blank?

        @registered ||= false #: bool?
        return if @registered

        claim_kind!(declared)
        @registered = true
        ActiveRecord::DynamicCredentials.install!
        klass = self
        ActiveRecord::DatabaseConfigurations.register_db_config_handler do |env_name, name, url, config|
          klass.build(env_name, name, url, config) if klass.handles?(config)
        end
        reload_configurations!
      end

      #: (String declared) -> void
      def self.claim_kind!(declared)
        owner = KIND_REGISTRY[declared]
        return if owner == self
        raise Error, %(kind "#{declared}" is already registered) if owner

        KIND_REGISTRY[declared] = self
      end
      private_class_method :claim_kind!

      #: (db_config config) -> bool
      def self.handles?(config)
        declared = kind
        return false if declared.blank?

        config[:dynamic_credential_kind].to_s == declared
      end

      # +url+ is merged first so explicit database.yml keys win. The merged
      # hash is what adapters receive, so host, username, and port from a URL
      # are available to +current_password+.
      #: (String env_name, String name, String? url, db_config config) -> instance
      def self.build(env_name, name, url, config)
        resolved = config
        if url.present?
          from_url = ActiveRecord::DatabaseConfigurations::ConnectionUrlResolver.new(url).to_hash
          resolved = from_url.merge(config)
        end
        new(env_name, name, resolved)
      end

      #: (String env_name, String name, db_config configuration_hash) -> void
      def initialize(env_name, name, configuration_hash)
        super
        @password_mutex = Mutex.new #: Mutex
        @password_fetched = false #: bool
        @password_expired = false #: bool
        @connection_password = nil #: String?
        @password_fetched_at = nil #: (Integer | Float)?
      end

      # Password embedded in the adapter when it is constructed. Rails copies
      # that hash into the driver parameters before the first handshake, which
      # is earlier than +reconnect!+.
      #: -> ActiveRecord::ConnectionAdapters::AbstractAdapter
      def new_connection
        build_connection(refresh: true)
      end

      # Memoized +current_password+. The external call happens on first use and
      # again after +expire_password!+ or +password_ttl+.
      #: -> String?
      def connection_password
        @password_mutex.synchronize do
          if @password_fetched && !@password_expired && !password_stale?
            return @connection_password
          end

          password = current_password
          @password_expired = false
          @password_fetched = true
          @password_fetched_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @connection_password = password
        end
      end

      #: -> void
      def expire_password!
        @password_mutex.synchronize { @password_expired = true }
      end

      # +nil+ keeps the password until a connection attempt rejects it.
      # Override for credentials that expire on their own, such as an IAM token.
      #: -> Integer?
      def password_ttl
        nil
      end

      # Password failures are sometimes reported as +NoDatabaseError+ because the
      # driver message mentions the database name. Hostname and pool timeouts are
      # not a reason to fetch again.
      #: (Exception error) -> bool
      def refresh_after_rejection?(error)
        return true if error.is_a?(ActiveRecord::NoDatabaseError)
        return false unless error.is_a?(ActiveRecord::ConnectionNotEstablished)
        return false if error.is_a?(ActiveRecord::ConnectionTimeoutError)
        return false if error.is_a?(ActiveRecord::ConnectionNotDefined)

        !error.message.to_s.include?("hostname")
      end

      #: -> String?
      def current_password
        raise NotImplementedError, "#{self.class} must implement #current_password"
      end

      #: -> void
      def self.reload_configurations!
        return unless defined?(Rails) && Rails.respond_to?(:application)
        application = Rails.application
        return unless application

        raw = application.config.database_configuration
        return if raw.blank?

        ActiveRecord::Base.configurations = raw
      end
      private_class_method :reload_configurations!

      private

      # +refresh+ stays on the stack. The config object is shared by every
      # thread in the pool, so a retry flag on it would let one handshake
      # cancel the other's retry.
      #: (refresh: bool) -> ActiveRecord::ConnectionAdapters::AbstractAdapter
      def build_connection(refresh:)
        adapter_class.new(configuration_hash_for_connection)
      rescue StandardError => error
        raise error unless refresh && refresh_after_rejection?(error)

        expire_password!
        build_connection(refresh: false)
      end

      #: -> db_config
      def configuration_hash_for_connection
        password = connection_password
        return configuration_hash if password.blank?

        configuration_hash.merge(password: password)
      end

      # A client built in the Puma master holds sockets from that process.
      # After fork, +Process.pid+ changes and the next use builds a new client
      # in the worker. The cached password is a string and stays.
      #: [Client] (Symbol ivar) { () -> Client } -> Client
      def fork_safe_client(ivar, &)
        pid_ivar = :"#{ivar}_owner_pid"
        owner_pid = instance_variable_get(pid_ivar)
        if owner_pid != Process.pid
          instance_variable_set(ivar, nil) if owner_pid
          instance_variable_set(pid_ivar, Process.pid)
        end

        cached = instance_variable_get(ivar) #: as Client?
        return cached if cached

        client = yield
        stored = client #: as BasicObject
        instance_variable_set(ivar, stored)
        client
      end

      #: -> bool
      def password_stale?
        ttl = password_ttl
        return false unless ttl && @password_fetched_at

        Process.clock_gettime(Process::CLOCK_MONOTONIC) - @password_fetched_at >= ttl
      end

      # Loaded on first use. The app Gemfile adds the SDK for the scheme it uses.
      #: (String gem_name) -> void
      def load_sdk!(gem_name)
        require gem_name
      rescue LoadError
        raise Error, %(Add gem "#{gem_name}" to your Gemfile)
      end
    end
  end
end
