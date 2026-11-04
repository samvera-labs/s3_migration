# frozen_string_literal: true

module S3Migration
  # Read-only check of one original file already in S3: the object must be readable, match the
  # recorded size, and match the stored checksum when one is present.
  class Auditor
    Result = Struct.new(:status, :problems, keyword_init: true)

    def initialize(original:, storage: Valkyrie::StorageAdapter)
      @original = original
      @storage = storage
    end

    # @return [Result] status is :ok, :problem or :not_in_s3
    def call
      return Result.new(status: :not_in_s3, problems: []) unless original.file_identifier.to_s.start_with?('shrine://')

      s3_file = storage.find_by(id: original.file_identifier)
      problems = size_problems(s3_file) + checksum_problems(s3_file)
      Result.new(status: problems.empty? ? :ok : :problem, problems:)
    end

    private

    attr_reader :original, :storage

    def size_problems(s3_file)
      recorded = Array(original.recorded_size)
      return [] if recorded.empty? || recorded.any? { |size| size.to_i == s3_file.size.to_i }

      ["size #{s3_file.size} != recorded #{recorded.join(' or ')}"]
    end

    def checksum_problems(s3_file)
      stored = StoredChecksum.all(original)
      return [] if stored.empty?

      actual = s3_digests(s3_file, stored)
      return [] if stored.any? { |checksum| actual[checksum.algorithm] == checksum.digest }

      stored.map { |checksum| "#{checksum.algorithm} #{actual[checksum.algorithm]} != stored #{checksum.digest}" }
    end

    # @return [Hash{String=>String}] the S3 object's digest for each algorithm the stored checksums use
    def s3_digests(s3_file, stored)
      algorithms = stored.map(&:algorithm).uniq
      digests = algorithms.map { |algorithm| StoredChecksum::ALGORITHMS.fetch(algorithm).first.new }
      algorithms.zip(s3_file.checksum(digests:)).to_h
    end
  end
end
