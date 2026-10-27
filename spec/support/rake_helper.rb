# frozen_string_literal: true

require 'rake'

# Loads the gem's rake tasks once. Ruby's coverage keeps only the last load of a file, so reloading per example
# would hide the lines that ran earlier.
module RakeHelper
  def self.application
    @application ||= Rake::Application.new.tap do |rake|
      Rake::TaskManager.record_task_metadata = true # the rake command turns this on; descriptions need it
      original = Rake.application
      Rake.application = rake
      Rake::Task.define_task(:environment)
      load File.expand_path('../../lib/tasks/s3_migration.rake', __dir__)
      Rake.application = original
    end
  end
end
