# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# CI sets these to test other versions: RAILS_VERSION=7.2, HYRAX_BRANCH=main.
gem 'hyrax', github: 'samvera/hyrax', branch: ENV['HYRAX_BRANCH'] if ENV['HYRAX_BRANCH']
gem 'rails', "~> #{ENV['RAILS_VERSION']}.0" if ENV['RAILS_VERSION']

group :development, :test do
  gem 'json', '< 3' # Valkyrie's old migrations pass JSON.generate a quirks_mode that json 3 removed
  gem 'pg'
  gem 'pry'
  gem 'rake'
  gem 'rspec', '~> 3.13'
  gem 'rubocop', '~> 1.69', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rake', require: false
  gem 'rubocop-rspec', require: false
  gem 'simplecov', require: false
end
