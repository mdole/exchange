require 'rails_helper'

describe ApplicationErrorEvent, type: :events do
  let(:application_error) do
    Errors::ApplicationError.new(
      :validation,
      :missing_region,
      { something: 'was wrong' },
      true
    )
  end
  let(:event) { ApplicationErrorEvent.new(application_error) }

  describe 'TOPIC' do
    it 'has correct topic' do
      expect(ApplicationErrorEvent::TOPIC).to eq 'commerce'
    end
  end

  describe 'to_json' do
    let(:parsed_json) { JSON.parse(event.to_json) }

    it 'has correct type' do
      expect(parsed_json['properties']['type']).to eq 'validation'
    end

    it 'has correct code' do
      expect(parsed_json['properties']['code']).to eq 'missing_region'
    end

    it 'has correct data' do
      expect(parsed_json['properties']['data']).to eq(
        'something' => 'was wrong'
      )
    end

    it 'has created_at' do
      expect(parsed_json['properties']['created_at']).not_to be_nil
    end
  end

  describe 'routing_key' do
    it 'has correct routing key' do
      expect(event.routing_key).to eq 'error.validation.missing_region'
    end
  end
end
