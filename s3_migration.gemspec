# frozen_string_literal: true

require_relative 'lib/s3_migration/version'

Gem::Specification.new do |spec|
  spec.name = 's3_migration'
  spec.version = S3Migration::VERSION
  spec.authors = ['Max Kadel']
  spec.email = ['max@notch8.com']

  spec.summary = 'Move Hyrax original files from disk storage to S3, verified and reversible.'
  spec.description = 'Rake tasks and jobs that copy original files from a Valkyrie disk storage adapter to an S3 ' \
                     '(valkyrie-shrine) adapter, verify every copy, then quarantine, roll back or purge the disk ' \
                     'copies from a manifest.'
  spec.homepage = 'https://github.com/samvera-labs/s3_migration'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata = {
    'source_code_uri' => "#{spec.homepage}/tree/main",
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir['lib/**/*', 'docs/**/*', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'hyrax', '>= 5.0', '< 6'
  spec.add_dependency 'valkyrie-shrine', '~> 1.1'
  spec.add_dependency 'zeitwerk', '~> 2.6'
end
