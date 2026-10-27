# frozen_string_literal: true

module S3Migration
  class Railtie < Rails::Railtie
    rake_tasks { load File.expand_path('../tasks/s3_migration.rake', __dir__) }
  end
end
