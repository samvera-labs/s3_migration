# frozen_string_literal: true

module S3Migration
  # The behaviour behind the s3_migration:* rake tasks. The environment and output are injected so it can be tested.
  class Tasks
    # Raised where a task should stop with a message instead of running.
    class Abort < StandardError; end

    ACTED_ON = %i[quarantined rolled_back].freeze

    # Runs one task for its rake wrapper, turning an Abort into a rake abort.
    def self.run(name)
      new.public_send(name)
    rescue Abort => e
      abort e.message
    end

    def initialize(env: ENV, out: $stdout)
      @env = env
      @out = out
    end

    def migrate
      require_storage!
      dry_run = flag('DRY_RUN')
      return enqueue unless dry_run || flag('INLINE')

      out.puts "[DRY RUN] No changes will be made.\n\n" if dry_run
      migrate_inline(dry_run:)
    end

    def verify
      counts = Hash.new(0)
      each_original(counts) do |file_set, original|
        result = Auditor.new(original:).call
        counts[result.status] += 1
        next false if result.status == :not_in_s3

        out.puts "  PROBLEM #{file_set.id} - #{result.problems.join('; ')}" if result.status == :problem
        true
      rescue StandardError => e
        counts[:problem] += 1
        out.puts "  PROBLEM #{file_set.id} - #{e.class}: #{e.message}"
        true
      end
      out.puts "\nOK: #{counts[:ok]}  Problems: #{counts[:problem]}  " \
               "Not yet in S3: #{counts[:not_in_s3]}  No original: #{counts[:no_original]}"
    end

    def report
      out.puts 'use | scheme | files | GB'
      StorageReport.call(progress: Progress.new).sort.each do |(use, scheme), (count, bytes)|
        out.puts "#{use} | #{scheme} | #{count} | #{(bytes / 1e9).round(2)}"
      end
    end

    def quarantine
      require_storage!
      out.puts "[DRY RUN] Nothing will be moved. Set APPLY=true to move.\n\n" unless flag('APPLY')
      each_entry('Quarantine', :quarantine)
    end

    def rollback
      require_storage!
      out.puts "[DRY RUN] Nothing will change. Set APPLY=true to roll back.\n\n" unless flag('APPLY')
      each_entry('Rolling back', :rollback)
    end

    def purge
      require_storage!
      apply = flag('APPLY')
      out.puts "[DRY RUN] Nothing will be deleted. Set APPLY=true to delete.\n\n" unless apply
      purged, kept = Quarantine.purge(apply:, min_age: min_age_days.days)
      out.puts "#{apply ? 'Deleted' : 'Would delete'}: #{purged}  Too recent: #{kept}"
    end

    private

    attr_reader :env, :out

    def flag(name, default: 'false')
      ActiveModel::Type::Boolean.new.cast(env.fetch(name, default))
    end

    def limit
      env['LIMIT']&.to_i
    end

    def min_age_days
      days = Float(env.fetch('MIN_AGE_DAYS', '14'), exception: false)
      unless days&.positive? && days.finite?
        raise Abort,
              "MIN_AGE_DAYS must be a positive number, got #{env['MIN_AGE_DAYS'].inspect}."
      end

      days
    end

    def require_storage!
      unless Valkyrie::StorageAdapter.storage_adapters.key?(:repository_s3)
        raise Abort,
              'Set up the :repository_s3 Valkyrie storage adapter first (see docs/migrating-files-to-s3.md).'
      end

      SourceStorage.adapter
    rescue SourceStorage::Unsupported => e
      raise Abort, e.message
    end

    def enqueue
      MigrateFilesJob.perform_later(limit:)
      out.puts 'Enqueued S3Migration::MigrateFilesJob'
    end

    def tally(counts)
      counts.map { |status, count| "#{status}: #{count}" }.join('  ')
    end

    def each_original(counts, &)
      progress = Progress.new(detail: -> { tally(counts) })
      on_error = lambda do |file_set, error|
        counts[:no_original] += 1
        out.puts "  NO_ORIGINAL #{file_set.id} - #{missing_original_detail(file_set, error)}"
      end
      S3Migration.each_original(limit:, progress:, on_error:, &)
    end

    def missing_original_detail(file_set, error)
      if file_set.try(:file_ids).blank?
        'file set has no files'
      elsif error.is_a?(Valkyrie::Persistence::ObjectNotFoundError)
        'original file record not found'
      else
        "#{error.class}: #{error.message}"
      end
    end

    def migrate_inline(dry_run:)
      counts = Hash.new(0)
      each_original(counts) do |file_set, original|
        result = FileMigrator.new(file_set:, original:, dry_run:).call
        counts[result.status] += 1
        next false if result.status == :already_migrated

        out.puts "  #{result.status.to_s.upcase} #{file_set.id} #{result.message}".rstrip
        true
      rescue StandardError => e
        counts[:error] += 1
        out.puts "  ERROR #{file_set.id} - #{e.class}: #{e.message}"
        true
      end
      out.puts "\nExamined #{counts.values.sum} file sets. #{tally(counts)}".strip
      out.puts 'No file sets were found; check the model names and query services.' if counts.empty?
    end

    def each_entry(label, action)
      counts = Hash.new(0)
      progress = Progress.new(detail: -> { tally(counts) })
      Manifest.new.each_entry do |entry|
        progress.tick
        status = Quarantine.new(entry, apply: flag('APPLY'),
                                       verify_sha: flag('VERIFY_SHA', default: 'true')).public_send(action)
        counts[status] += 1
        out.puts "  #{label} #{entry[:file_set_id]}" if ACTED_ON.include?(status)
      rescue StandardError => e
        counts[:error] += 1
        out.puts "  ERROR #{entry[:file_set_id]} - #{e.class}: #{e.message}"
      end
      out.puts "\n#{tally(counts)}".strip
      out.puts 'No manifest entries found.' if counts.empty?
    end
  end
end
