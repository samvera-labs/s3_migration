# frozen_string_literal: true

module S3Migration
  # A checksum Hyrax recorded for a file at characterization (FileMetadata#checksum). FITS reports
  # a bare MD5 hex string; an explicit urn:<algorithm>: prefix is also understood. Anything else
  # (unknown prefix, wrong length) is treated as no checksum rather than as a mismatch. A file characterized
  # more than once can record several, so callers accept a match against any of them.
  class StoredChecksum
    ALGORITHMS = { 'md5' => [Digest::MD5, 32], 'sha1' => [Digest::SHA1, 40], 'sha256' => [Digest::SHA256, 64] }.freeze

    attr_reader :algorithm, :digest

    # @return [Array<StoredChecksum>] every usable checksum, empty when there is none
    def self.all(original)
      Array(original.checksum).filter_map { |value| parse(value) }
    end

    def self.parse(value)
      match = /\A(?:urn:(?<algorithm>md5|sha1|sha256):)?(?<digest>\h+)\z/i.match(value.to_s.strip)
      return unless match

      algorithm = match[:algorithm]&.downcase || 'md5'
      digest = match[:digest].downcase
      new(algorithm, digest) if digest.length == ALGORITHMS.fetch(algorithm).last
    end
    private_class_method :parse

    def initialize(algorithm, digest)
      @algorithm = algorithm
      @digest = digest
    end

    def digest_class
      ALGORITHMS.fetch(algorithm).first
    end

    def to_s
      "#{algorithm}:#{digest}"
    end
  end
end
