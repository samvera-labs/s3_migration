# frozen_string_literal: true

# Thin wrappers: the work lives in S3Migration::Tasks. See docs/migrating-files-to-s3.md.
namespace :s3_migration do
  desc <<~DESC
    Move original files from the plain disk storage adapter (disk:// ids) to the :repository_s3 adapter. By default this
    enqueues jobs (one per file set; set S3_MIGRATION_QUEUE to use a dedicated queue). Each upload is
    verified by SHA-256 read-back, and against the stored characterization checksum, before the identifier
    is switched; the disk copy is never touched.
    Env: DRY_RUN=true runs inline and only reports; INLINE=true runs inline for real; LIMIT=<n> files.
  DESC
  task migrate: :environment do
    S3Migration::Tasks.run(:migrate)
  end

  desc <<~DESC
    Read-only audit of originals already in S3: object readable, recorded size and stored checksum match.
    Get zero problems before deleting anything from disk. Env: LIMIT=<n> files.
  DESC
  task verify: :environment do
    S3Migration::Tasks.run(:verify)
  end

  desc 'Read-only report of file storage by file use and scheme (disk, shrine, ...).'
  task report: :environment do
    S3Migration::Tasks.run(:report)
  end

  desc <<~DESC
    Move the disk copies of manifested files to <storage>/.quarantine after re-checking the database
    and the S3 object against the manifest. Dry run unless APPLY=true. VERIFY_SHA=false skips the hash.
  DESC
  task quarantine: :environment do
    S3Migration::Tasks.run(:quarantine)
  end

  desc 'Undo a migration from the manifest (restores the disk copy and id, removes the unused upload). Dry run unless APPLY=true.'
  task rollback: :environment do
    S3Migration::Tasks.run(:rollback)
  end

  desc 'Permanently delete the quarantined copies of manifested files older than MIN_AGE_DAYS (default 14). Dry run unless APPLY=true.'
  task purge: :environment do
    S3Migration::Tasks.run(:purge)
  end
end
