# frozen_string_literal: true

RSpec.describe S3Migration do
  it 'has a semantic version' do
    expect(S3Migration::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
