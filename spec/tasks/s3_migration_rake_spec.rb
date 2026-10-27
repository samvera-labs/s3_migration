# frozen_string_literal: true

RSpec.describe 'the s3_migration rake tasks', type: :task do
  shared_examples 'a task wrapper' do |name|
    let(:task) { RakeHelper.application["s3_migration:#{name}"] }

    before do
      allow(S3Migration::Tasks).to receive(:run)
      task.reenable
    end

    it 'runs through S3Migration::Tasks' do
      task.invoke

      expect(S3Migration::Tasks).to have_received(:run).with(name)
    end

    it 'is described' do
      expect(task.comment).to be_present
    end
  end

  %i[migrate verify report quarantine rollback purge].each do |name|
    describe name.to_s do
      it_behaves_like 'a task wrapper', name
    end
  end
end
