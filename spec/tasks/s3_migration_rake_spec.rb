# frozen_string_literal: true

require 'rake'

RSpec.describe 'the s3_migration rake tasks' do
  # Loaded once: Ruby's coverage keeps only the last load of a file, so reloading per example would hide the lines.
  rake = Rake::Application.new
  Rake::TaskManager.record_task_metadata = true # the rake command turns this on; descriptions need it
  original_application = Rake.application
  Rake.application = rake
  Rake::Task.define_task(:environment)
  load File.expand_path('../../lib/tasks/s3_migration.rake', __dir__)
  Rake.application = original_application

  before { allow(S3Migration::Tasks).to receive(:run) }

  %i[migrate verify report quarantine rollback purge].each do |name|
    task_name = "s3_migration:#{name}"

    it "runs #{name} through S3Migration::Tasks" do
      rake[task_name].reenable
      rake[task_name].invoke

      expect(S3Migration::Tasks).to have_received(:run).with(name)
    end

    it "describes #{name}" do
      expect(rake[task_name].comment).to be_present
    end
  end
end
