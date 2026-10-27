# frozen_string_literal: true

# Enqueues a S3Migration::MigrateFileSetJob for every file set whose original is still on disk.
module S3Migration
  class MigrateFilesJob < ActiveJob::Base
    queue_as { ENV.fetch('S3_MIGRATION_QUEUE', 'default') }

    def perform(limit: nil)
      enqueued = 0
      S3Migration.each_file_set do |file_set|
        break if limit && enqueued >= limit
        next unless on_disk?(file_set)

        MigrateFileSetJob.perform_later(file_set.id.to_s)
        enqueued += 1
      end
      Rails.logger.info("[S3Migration] enqueued #{enqueued} file sets")
      enqueued
    end

    private

    def on_disk?(file_set)
      on_error = ->(fs, error) { Rails.logger.warn("[S3Migration] #{fs.id} has no readable original: #{error.class}") }
      S3Migration.original_for(file_set, on_error:)&.file_identifier.then { |identifier| identifier && S3Migration::SourceStorage.handles?(identifier) }
    end
  end
end
