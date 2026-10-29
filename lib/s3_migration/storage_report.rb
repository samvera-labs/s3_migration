# frozen_string_literal: true

module S3Migration
  # Tallies the files by use (original, thumbnail, ...) and storage scheme.
  class StorageReport
    # @param progress [S3Migration::Progress, nil] ticked once per file set
    # @return [Hash{Array<String>=>Array<Integer>}] { [use, scheme] => [file count, bytes] }
    def self.call(progress: nil)
      totals = Hash.new { |hash, key| hash[key] = [0, 0] }
      S3Migration.each_file_set do |file_set|
        progress&.tick
        add_files(totals, files_for(file_set))
      end
      totals
    end

    def self.add_files(totals, files)
      totals[['(file record missing)', '-']][0] += 1 unless files
      files&.each { |file| add_file(totals, file) }
    end

    def self.add_file(totals, file)
      count_and_bytes = totals[[use_for(file), file.file_identifier.to_s[/\A[a-z]+(?=:)/].to_s]]
      count_and_bytes[0] += 1
      count_and_bytes[1] += file.recorded_size.first.to_i
    end

    def self.files_for(file_set)
      S3Migration.find_files(file_set:)
    rescue Valkyrie::Persistence::ObjectNotFoundError
      nil
    end

    def self.use_for(file)
      Array(file.pcdm_use).map { |uri| uri.to_s.split('#').last }.join(',')
    end
  end
end
