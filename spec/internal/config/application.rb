# frozen_string_literal: true

require_relative 'boot'
require 'rails/all'
require 'sprockets/railtie'
require 'hyrax'
require 's3_migration'

module Internal
  # A bare Rails app that boots Hyrax with the Postgres Valkyrie adapter and no Fedora, Solr or Redis.
  class Application < Rails::Application
    config.load_defaults 7.2
    config.add_autoload_paths_to_load_path = true # Hyrax's initializers require files from app/models
    config.root = File.expand_path('..', __dir__)
    config.eager_load = false
    config.secret_key_base = 'test'
    config.active_job.queue_adapter = :test
    config.logger = Logger.new(nil)
  end
end
