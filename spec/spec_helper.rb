# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  track_files '{lib}/**/*.{rb,rake}'
  add_filter '/spec/'
  add_filter 'lib/s3_migration/version.rb' # the gemspec loads it before coverage starts, so it cannot be measured
  minimum_coverage 100 # lines
end

ENV['RAILS_ENV'] = 'test'
require_relative 'internal/config/environment'

begin
  ActiveRecord::Base.connection.verify!
rescue ActiveRecord::NoDatabaseError # a fresh Postgres, such as CI's service container, has only its default database
  ActiveRecord::Tasks::DatabaseTasks.create(ActiveRecord::Base.configurations.configs_for(env_name: 'test').first)
  ActiveRecord::Base.establish_connection
end

ActiveRecord::Schema.verbose = false
load Rails.root.join('db/schema.rb') unless ActiveRecord::Base.connection.table_exists?(:orm_resources)

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = '.rspec_status'
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |m| m.verify_partial_doubles = true }
end
