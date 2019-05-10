require 'rails_helper'

describe Address do
  let(:address_params) do
    {
      country: 'US',
      region: 'NY',
      city: 'New York',
      address_line1: '401 Broadway',
      postal_code: '10013'
    }
  end
  let(:address) { Address.new(address_params) }
  let(:address_attributes) do
    %i[country region city street_line1 street_line2 postal_code]
  end
  describe '#initialize' do
    context 'with an empty address' do
      it 'sets the address attributes to nil' do
        empty_address = Address.new({})
        address_attributes.each do |attr|
          expect(empty_address.instance_variable_get("@#{attr}")).to be_nil
        end
      end
    end
  end
  describe '#parse' do
    let(:location) { { country: 'USA', region: 'FL' } }
    it 'returns a hash with the appropriate keys' do
      parsed_address = address.send(:parse, location)
      address_attributes.each do |key|
        expect(parsed_address.key?(key)).to eq true
      end
    end
    it 'returns the address with Carmen country code' do
      expect(address.send(:parse, location)[:country]).to eq 'US'
    end
    context 'with a US or CA address' do
      it 'returns the address with the Carmen region code' do
        expect(address.send(:parse, location)[:region]).to eq 'FL'
      end
    end
  end
  describe '#parse_region' do
    let(:united_states) { Carmen::Country.coded('US') }
    it 'strips trailing and leading whitespace from the region' do
      region = ' New York   '
      expect(address.send(:parse_region, united_states, region)).to eq 'NY'
    end
    context 'with a country that is not US or CA' do
      it 'returns the region unmodified' do
        australia = Carmen::Country.coded('AU')
        expect(
          address.send(:parse_region, australia, 'Northern Territory')
        ).to eq 'Northern Territory'
      end
    end
    context 'with a country that is US or CA' do
      it 'returns the region code if the country is US or CA' do
        canada = Carmen::Country.coded('CA')
        expect(address.send(:parse_region, united_states, 'Florida')).to eq 'FL'
        expect(address.send(:parse_region, united_states, 'FL')).to eq 'FL'
        expect(address.send(:parse_region, canada, 'Quebec')).to eq 'QC'
        expect(address.send(:parse_region, canada, 'QC')).to eq 'QC'
      end
      it 'returns nil if the region is not found' do
        expect(
          address.send(:parse_region, united_states, 'Floridada')
        ).to be_nil
      end
    end
  end
  describe '#==' do
    context 'with an address that has the same address attributes' do
      context 'with an empty address' do
        it 'returns true' do
          expect(Address.new({}) == Address.new({})).to be true
        end
      end
      it 'returns true' do
        expect(
          Address.new(address_params) == Address.new(address_params)
        ).to be true
      end
    end
    context 'with an address that does not have the same address attributes' do
      let(:mismatched_address_params) do
        {
          country: 'US',
          region: 'NY',
          city: 'New York',
          address_line1: 'SOMEWHERE ELSE',
          postal_code: '10013'
        }
      end
      it 'returns false' do
        expect(
          Address.new(address_params) == Address.new(mismatched_address_params)
        ).to be false
      end
    end
  end
end
