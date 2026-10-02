# frozen_string_literal: true

require_relative "lib/active_record/dynamic_credentials/version"

Gem::Specification.new do |spec|
  spec.name = "activerecord-dynamic_credentials"
  spec.version = ActiveRecord::DynamicCredentials::VERSION
  spec.authors = [ "Wilson Point" ]
  spec.summary = "Refresh Active Record database credentials on each connection"
  spec.description = <<~DESC
    Prepends ActiveRecord::ConnectionAdapters::AbstractAdapter#reconnect! so on-the-fly
    credentials (Secrets Manager, RDS IAM auth tokens, or your own) are applied before
    any adapter opens a socket. Scheme selection comes from database.yml.
  DESC
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib}/**/*", "README.md"].select { |f| File.file?(f) }
  end
  spec.require_paths = [ "lib" ]

  spec.add_dependency "activerecord", ">= 7.1"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "sorbet", "~> 0.6"
  spec.add_development_dependency "tapioca", "~> 0.17"
end
