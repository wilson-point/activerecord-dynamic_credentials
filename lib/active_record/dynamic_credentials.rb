# typed: strict
# frozen_string_literal: true

require "active_record"
require "active_record/database_configurations"
require "active_record/connection_adapters/abstract_adapter"
require_relative "dynamic_credentials/version"
require_relative "dynamic_credentials/reconnect"
require_relative "dynamic_credentials/config"

module ActiveRecord
  module DynamicCredentials
    class << self
      #: -> void
      def install!
        return if installed?

        ConnectionAdapters::AbstractAdapter.prepend(Reconnect)
      end

      #: -> bool
      def installed?
        ConnectionAdapters::AbstractAdapter.ancestors.include?(Reconnect)
      end
    end
  end
end

require_relative "dynamic_credentials/railtie" if defined?(Rails::Railtie)

ActiveRecord::DynamicCredentials.install!
