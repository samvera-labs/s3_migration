# frozen_string_literal: true

RSpec.describe S3Migration::MigrateFilesJob do
  let(:file_sets) { %w[disk1 shrine disk2 none disk3].map { |id| double(id, id: Valkyrie::ID.new(id)) } }
  let(:originals) do
    {
      'disk1' => double(file_identifier: Valkyrie::ID.new('disk:///a')),
      'shrine' => double(file_identifier: Valkyrie::ID.new('shrine://x/y')),
      'disk2' => double(file_identifier: Valkyrie::ID.new('disk:///b')),
      'none' => nil,
      'disk3' => double(file_identifier: Valkyrie::ID.new('disk:///c'))
    }
  end

  before do
    allow(S3Migration::SourceStorage).to receive(:adapter).and_return(Valkyrie::Storage::Disk.new(base_path: '/'))
    allow(S3Migration).to receive(:each_file_set) { |&block| file_sets.each(&block) }
    allow(S3Migration).to receive(:find_original_file) { |file_set:| originals[file_set.id.to_s] }
    allow(S3Migration::MigrateFileSetJob).to receive(:perform_later)
  end

  it 'enqueues a job for each file set whose original is still on disk' do
    expect(described_class.perform_now).to eq 3

    %w[disk1 disk2 disk3].each { |id| expect(S3Migration::MigrateFileSetJob).to have_received(:perform_later).with(id) }
    expect(S3Migration::MigrateFileSetJob).not_to have_received(:perform_later).with('shrine')
  end

  it 'stops at the limit' do
    expect(described_class.perform_now(limit: 2)).to eq 2

    expect(S3Migration::MigrateFileSetJob).to have_received(:perform_later).twice
  end

  it 'skips file sets that disappear while enumerating' do
    allow(S3Migration).to receive(:find_original_file).with(file_set: file_sets.first)
                                                      .and_raise(Valkyrie::Persistence::ObjectNotFoundError)

    expect(described_class.perform_now).to eq 2
  end
end
