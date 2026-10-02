# typed: strict
# frozen_string_literal: true

module ActiveRecord
  module DynamicCredentials
    class Railtie < Rails::Railtie
      initializer "active_record.dynamic_credentials" do
        ActiveRecord::DynamicCredentials.install!
      end
    end
  end
end
