# activerecord-dynamic_credentials

AR-Dynamic Credentials allows authenticating with your database with dynamic credentials. It works with any connection adapter or database driver, and it handles reconnecting. It uses a small monkey patch of Active Records' `AbstractAdapter` class, and otherwise defines and registers custom `DatabaseConfiguration` classes.

It includes two prebuilt configurations for fetching passwords from AWS Secrets Manager and AWS RDS IAM authentication, but also allows defining and registering custom configurations. It only fetches secrets at connection time, avoiding unnecessary api calls and cost. It allows configuring different authentication schemes on each database.yml block, so different environments are supported.

First, add the gem:
```ruby
gem 'activerecord-dynamic_credentials', github: 'wilson-point/activerecord-dynamic_credentials'
```

Then configure your authentication scheme.

## RDS IAM

```ruby
# Gemfile
gem "aws-sdk-rds"
```

```ruby
# config/initializers/dynamic_credentials.rb
require "active_record/dynamic_credentials/iam_auth"
```

```yaml
production:
  adapter: postgresql
  host: db.example.com
  port: 5432
  database: app_production
  username: app_iam
  aws_region: us-east-2 # optional when AWS_REGION is set
  dynamic_credential_kind: iam_auth
```

## Secrets Manager

```ruby
# Gemfile
gem "aws-sdk-secretsmanager"
```

```ruby
# config/initializers/dynamic_credentials.rb
require "active_record/dynamic_credentials/secrets_manager"
```

```yaml
production:
  adapter: postgresql
  host: db.example.com
  port: 5432
  database: app_production
  username: app
  password_secret_arn: <%= ENV["DATABASE_MASTER_USER_PASSWORD_SECRET_ARN"] %>
  dynamic_credential_kind: secrets_manager
```

The secret is RDS JSON (`{"password":"..."}`) or a raw password. A fetch failure keeps the `password:` from this file.

## Custom

```ruby
class VaultConfig < ActiveRecord::DynamicCredentials::Config
  kind :vault

  def current_password
    Vault.logical.read(configuration_hash[:vault_path]).data[:password]
  end
end

VaultConfig.register!
```

```yaml
production:
  dynamic_credential_kind: vault
  vault_path: secret/data/db
```

## Contributing

```
bundle install
bundle exec rake test
bundle exec srb tc
```

Ruby is pinned in `.ruby-version`. Pull requests that add a prebuilt for another common scheme are welcome.
