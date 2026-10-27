# frozen_string_literal: true

module S3Migration
  # Registers the s3_migration:* rake tasks with the host application.
  class Railtie < Rails::Railtie
    rake_tasks { load File.expand_path('../tasks/s3_migration.rake', __dir__) }
  end
end
