# frozen_string_literal: true

RSpec.describe S3Migration::Quarantine, '.purge' do
  let(:base) { Dir.mktmpdir }
  let(:old_file) { File.join(base, '.quarantine', 'old.bin') }
  let(:recent_file) { File.join(base, '.quarantine', 'sub', 'recent.bin') }
  let(:other_scope_file) { File.join(base, '.quarantine', 'other', 'theirs.bin') }
  let(:manifest) { instance_double(S3Migration::Manifest, each_entry: entries.each) }
  let(:entries) do
    [{ old_id: "disk://#{base}/old.bin" }, { old_id: "disk://#{base}/sub/recent.bin" },
     { old_id: 'disk:///elsewhere/x.bin' }]
  end

  before do
    allow(S3Migration::SourceStorage).to receive(:adapter).and_return(Valkyrie::Storage::Disk.new(base_path: base))
    [old_file, recent_file, other_scope_file].each do |file|
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, 'x')
    end
    File.utime(30.days.ago.to_time, 30.days.ago.to_time, old_file, other_scope_file)
  end

  after { FileUtils.remove_entry(base) }

  it 'deletes only manifested files older than the minimum age' do
    expect(described_class.purge(apply: true, min_age: 14.days, base:, manifest:)).to eq [1, 1]
    expect(File.exist?(old_file)).to be false
    expect(File.exist?(recent_file)).to be true
  end

  it 'leaves quarantined files that are not in the manifest, however old' do
    described_class.purge(apply: true, min_age: 14.days, base:, manifest:)
    expect(File.exist?(other_scope_file)).to be true
  end

  it 'removes directories it emptied and no others' do
    File.utime(30.days.ago.to_time, 30.days.ago.to_time, recent_file)
    described_class.purge(apply: true, min_age: 14.days, base:, manifest:)
    expect(Dir.exist?(File.dirname(recent_file))).to be false
    expect(Dir.exist?(File.join(base, '.quarantine'))).to be true
  end

  it 'counts a file another purge already deleted as purged' do
    allow(File).to receive(:delete).and_call_original
    allow(File).to receive(:delete).with(old_file).and_raise(Errno::ENOENT)

    expect(described_class.purge(apply: true, min_age: 14.days, base:, manifest:)).to eq [1, 1]
  end

  it 'does nothing on a dry run' do
    expect(described_class.purge(apply: false, min_age: 14.days, base:, manifest:)).to eq [1, 1]
    expect(File.exist?(old_file)).to be true
  end

  it 'handles a base path containing glob characters' do
    odd_base = File.join(base, 'a[b]*?')
    file = File.join(odd_base, '.quarantine', 'old.bin')
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, 'x')
    File.utime(30.days.ago.to_time, 30.days.ago.to_time, file)
    odd_manifest = instance_double(S3Migration::Manifest, each_entry: [{ old_id: "disk://#{odd_base}/old.bin" }].each)

    expect(described_class.purge(apply: true, min_age: 14.days, base: odd_base, manifest: odd_manifest)).to eq [1, 0]
    expect(File.exist?(file)).to be false
  end

  it 'refuses a minimum age that is not positive, deleting nothing' do
    [0.days, -1.day, nil].each do |min_age|
      expect do
        described_class.purge(apply: true, min_age:, base:,
                              manifest:)
      end.to raise_error(ArgumentError, /min_age must be positive/)
    end
    expect(File.exist?(old_file)).to be true
  end
end
