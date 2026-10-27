# frozen_string_literal: true

RSpec.describe S3Migration::Tasks do
  subject(:tasks) { described_class.new(env:, out:) }

  let(:env) { {} }
  let(:out) { StringIO.new }
  let(:file_set) { double('file set', id: Valkyrie::ID.new('fs1'), file_ids: ['f1']) }
  let(:original) { double('original') }
  let(:output) { out.string }

  def stub_storage
    allow(Valkyrie::StorageAdapter).to receive(:storage_adapters).and_return(repository_s3: double('s3'))
    allow(S3Migration::SourceStorage).to receive(:adapter)
  end

  def each_original_yields(*pairs, errors: [])
    allow(S3Migration).to receive(:each_original) do |on_error:, **, &block|
      errors.each { |error_file_set, error| on_error.call(error_file_set, error) }
      pairs.each { |pair| block.call(*pair) }
    end
  end

  def migrator_returns(status, message = nil)
    result = S3Migration::FileMigrator::Result.new(status:, message:)
    allow(S3Migration::FileMigrator).to receive(:new).and_return(double('migrator', call: result))
  end

  describe '.run' do
    it 'runs the named task' do
      runner = instance_double(described_class, report: nil)
      allow(described_class).to receive(:new).and_return(runner)

      described_class.run(:report)

      expect(runner).to have_received(:report)
    end

    it 'turns an abort into a rake abort with its message' do
      runner = instance_double(described_class)
      allow(runner).to receive(:purge).and_raise(described_class::Abort, 'stop here')
      allow(described_class).to receive(:new).and_return(runner)

      allow(described_class).to receive(:abort)

      described_class.run(:purge)

      expect(described_class).to have_received(:abort).with('stop here')
    end
  end

  describe '#migrate' do
    it 'stops when the S3 adapter is not registered' do
      allow(Valkyrie::StorageAdapter).to receive(:storage_adapters).and_return({})

      expect { tasks.migrate }.to raise_error(described_class::Abort, /:repository_s3/)
    end

    it 'stops when the source storage is not supported' do
      allow(Valkyrie::StorageAdapter).to receive(:storage_adapters).and_return(repository_s3: double('s3'))
      allow(S3Migration::SourceStorage).to receive(:adapter).and_raise(S3Migration::SourceStorage::Unsupported, 'versioned disk')

      expect { tasks.migrate }.to raise_error(described_class::Abort, 'versioned disk')
    end

    context 'with the storage in place' do
      before { stub_storage }

      it 'enqueues the listing job, passing the limit' do
        env['LIMIT'] = '5'
        allow(S3Migration::MigrateFilesJob).to receive(:perform_later)

        tasks.migrate

        expect(S3Migration::MigrateFilesJob).to have_received(:perform_later).with(limit: 5)
        expect(output).to include('Enqueued S3Migration::MigrateFilesJob')
      end

      it 'reports what a dry run would do' do
        env['DRY_RUN'] = 'true'
        each_original_yields([file_set, original])
        migrator_returns(:would_migrate)

        tasks.migrate

        expect(output).to include('[DRY RUN]', 'WOULD_MIGRATE fs1', 'Examined 1 file sets. would_migrate: 1')
      end

      it 'migrates inline, staying quiet about files already in S3' do
        env['INLINE'] = 'true'
        each_original_yields([file_set, original], [file_set, original])
        results = [S3Migration::FileMigrator::Result.new(status: :migrated, message: 'moved'),
                   S3Migration::FileMigrator::Result.new(status: :already_migrated)]
        migrator = double('migrator')
        allow(S3Migration::FileMigrator).to receive(:new).and_return(migrator)
        allow(migrator).to receive(:call).and_return(*results)

        tasks.migrate

        expect(output).to include('MIGRATED fs1 moved', 'migrated: 1  already_migrated: 1')
        expect(output).not_to include('ALREADY_MIGRATED')
      end

      it 'reports an error and carries on' do
        env['INLINE'] = 'true'
        each_original_yields([file_set, original])
        allow(S3Migration::FileMigrator).to receive(:new).and_return(double('migrator').tap { |m| allow(m).to receive(:call).and_raise('boom') })

        tasks.migrate

        expect(output).to include('ERROR fs1 - RuntimeError: boom', 'error: 1')
      end

      it 'says so when there is nothing to migrate' do
        env['INLINE'] = 'true'
        each_original_yields

        tasks.migrate

        expect(output).to include('No file sets were found')
      end

      it 'explains why a file set has no usable original' do
        env['INLINE'] = 'true'
        empty = double('empty', id: Valkyrie::ID.new('fs0'), file_ids: [])
        each_original_yields(errors: [[empty, StandardError.new],
                                      [file_set, Valkyrie::Persistence::ObjectNotFoundError.new],
                                      [file_set, RuntimeError.new('bad')]])

        tasks.migrate

        expect(output).to include('NO_ORIGINAL fs0 - file set has no files',
                                  'NO_ORIGINAL fs1 - original file record not found',
                                  'NO_ORIGINAL fs1 - RuntimeError: bad')
      end
    end
  end

  describe '#verify' do
    let(:fine) { double('fine') }
    let(:broken) { double('broken') }
    let(:elsewhere) { double('elsewhere') }
    let(:crashing) { double('crashing') }

    def audit(result = nil, raises: nil)
      auditor = double('auditor')
      raises ? allow(auditor).to(receive(:call).and_raise(raises)) : allow(auditor).to(receive(:call).and_return(result))
      auditor
    end

    it 'counts what it finds and prints the problems' do
      each_original_yields([file_set, fine], [file_set, broken], [file_set, elsewhere], [file_set, crashing])
      auditors = { fine => audit(S3Migration::Auditor::Result.new(status: :ok, problems: [])),
                   broken => audit(S3Migration::Auditor::Result.new(status: :problem, problems: ['size differs', 'no object'])),
                   elsewhere => audit(S3Migration::Auditor::Result.new(status: :not_in_s3, problems: [])),
                   crashing => audit(raises: 'boom') }
      allow(S3Migration::Auditor).to receive(:new) { |original:| auditors.fetch(original) }

      tasks.verify

      expect(output).to include('PROBLEM fs1 - size differs; no object', 'PROBLEM fs1 - RuntimeError: boom',
                                'OK: 1  Problems: 2  Not yet in S3: 1  No original: 0')
    end
  end

  describe '#report' do
    it 'prints a row per use and scheme, sorted, with gigabytes' do
      allow(S3Migration::StorageReport).to receive(:call).and_return(%w[ThumbnailImage disk] => [3, 500_000_000],
                                                                    %w[OriginalFile shrine] => [2, 3_000_000_000])

      tasks.report

      expect(output.lines.map(&:chomp)).to eq ['use | scheme | files | GB', 'OriginalFile | shrine | 2 | 3.0', 'ThumbnailImage | disk | 3 | 0.5']
    end
  end

  shared_examples 'a manifest-driven task' do |action:, label:, banner:|
    let(:entries) { [{ file_set_id: 'fs1' }, { file_set_id: 'fs2' }, { file_set_id: 'fs3' }] }
    let(:statuses) { { 'fs1' => :quarantined, 'fs2' => :rolled_back, 'fs3' => :skipped } }

    before do
      stub_storage
      manifest = double('manifest')
      allow(manifest).to receive(:each_entry) { |&block| entries.each(&block) }
      allow(S3Migration::Manifest).to receive(:new).and_return(manifest)
      allow(S3Migration::Quarantine).to receive(:new) do |entry, **|
        double('quarantine').tap { |q| allow(q).to receive(action).and_return(statuses.fetch(entry[:file_set_id])) }
      end
    end

    it 'is a dry run unless APPLY is set' do
      tasks.public_send(action)

      expect(output).to include('[DRY RUN]')
      expect(S3Migration::Quarantine).to have_received(:new).with(anything, apply: false, verify_sha: true).exactly(3).times
    end

    it 'passes APPLY and VERIFY_SHA on' do
      env.merge!('APPLY' => 'true', 'VERIFY_SHA' => 'false')

      tasks.public_send(action)

      expect(output).not_to include('[DRY RUN]')
      expect(S3Migration::Quarantine).to have_received(:new).with(anything, apply: true, verify_sha: false).exactly(3).times
    end

    it 'prints the files it acted on and tallies every outcome' do
      tasks.public_send(action)

      expect(output).to include("#{label} fs1", "#{label} fs2", 'quarantined: 1  rolled_back: 1  skipped: 1')
      expect(output).not_to include("#{label} fs3")
    end

    it 'reports an error and carries on' do
      allow(S3Migration::Quarantine).to receive(:new).and_raise('boom')

      tasks.public_send(action)

      expect(output).to include('ERROR fs1 - RuntimeError: boom', 'error: 3')
    end

    it 'says so when the manifest is empty' do
      entries.clear

      tasks.public_send(action)

      expect(output).to include('No manifest entries found.')
    end

    it 'names what the dry run holds back' do
      tasks.public_send(action)

      expect(output).to include(banner)
    end
  end

  describe '#quarantine' do
    it_behaves_like 'a manifest-driven task', action: :quarantine, label: 'Quarantine', banner: 'Nothing will be moved'
  end

  describe '#rollback' do
    it_behaves_like 'a manifest-driven task', action: :rollback, label: 'Rolling back', banner: 'Nothing will change'
  end

  describe '#purge' do
    before do
      stub_storage
      allow(S3Migration::Quarantine).to receive(:purge).and_return([2, 1])
    end

    it 'is a dry run with a 14 day soak by default' do
      tasks.purge

      expect(S3Migration::Quarantine).to have_received(:purge).with(apply: false, min_age: 14.days)
      expect(output).to include('[DRY RUN]', 'Would delete: 2  Too recent: 1')
    end

    it 'deletes when APPLY is set, with the given soak' do
      env.merge!('APPLY' => 'true', 'MIN_AGE_DAYS' => '0.5')

      tasks.purge

      expect(S3Migration::Quarantine).to have_received(:purge).with(apply: true, min_age: 0.5.days)
      expect(output).to include('Deleted: 2  Too recent: 1')
    end

    ['abc', '', '0', '-3', 'NaN', 'Infinity'].each do |value|
      it "refuses MIN_AGE_DAYS=#{value.inspect}, deleting nothing" do
        env.merge!('APPLY' => 'true', 'MIN_AGE_DAYS' => value)

        expect { tasks.purge }.to raise_error(described_class::Abort, /MIN_AGE_DAYS must be a positive number/)
        expect(S3Migration::Quarantine).not_to have_received(:purge)
      end
    end
  end
end
