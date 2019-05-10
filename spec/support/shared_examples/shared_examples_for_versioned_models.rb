RSpec.shared_examples 'a papertrail versioned model',
                      versioning: true do |model_symbol|
  let(:model_instance) { Fabricate(model_symbol) }

  it 'creates a version record on data change' do
    expect { model_instance.update!(updated_at: Time.current) }.to change {
      model_instance.versions.count
    }.by(1)
  end

  it 'saves the exact value in item_id as the version record' do
    model_instance.update!(updated_at: Time.current)
    last_version = model_instance.versions.last

    expect(last_version.item_id).to eq(model_instance.id)
  end

  it 'directly saves the data changed to versions' do
    model_instance.update!(updated_at: Time.current)
    last_version = model_instance.versions.last

    expect(last_version.object_changes).to have_key('updated_at')
  end
end
