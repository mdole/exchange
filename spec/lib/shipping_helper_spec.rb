require 'rails_helper'
require 'support/gravity_helper'

describe ShippingHelper, type: :services do
  let(:us_shipping) do
    Address.new(
      street_line1: '401 Broadway',
      country: 'US',
      city: 'New York',
      region: 'NY',
      postal_code: '10013'
    )
  end
  let(:italy_shipping) do
    Address.new(
      street_line1: '3101 A St',
      country: 'IT',
      city: 'Como',
      region: 'Lombardy',
      postal_code: '99503'
    )
  end
  let(:artwork_in_italy_config) do
    {
      _id: 'a-1',
      domestic_shipping_fee_cents: 100_00,
      international_shipping_fee_cents: 500_00,
      location: { country: 'IT', city: 'Milan', state: 'Lombardy' }
    }
  end
  let(:continental_us_artwork_config) do
    {
      _id: 'a-2',
      domestic_shipping_fee_cents: 100_00,
      international_shipping_fee_cents: 500_00,
      location: { country: 'US', city: 'Brooklyn', state: 'NY' }
    }
  end
  let(:missing_artwork_location_config) do
    {
      _id: 'a-3',
      domestic_shipping_fee_cents: 100_00,
      international_shipping_fee_cents: 500_00,
      location: nil
    }
  end

  let(:artwork) { gravity_v1_artwork }
  let(:continental_us_artwork) do
    gravity_v1_artwork(continental_us_artwork_config)
  end
  let(:artwork_in_italy) { gravity_v1_artwork(artwork_in_italy_config) }
  let(:artwork_missing_location) do
    gravity_v1_artwork(missing_artwork_location_config)
  end
  describe '#calculate' do
    context 'with pickup fulfillment type' do
      it 'returns 0' do
        expect(ShippingHelper.calculate(artwork, Order::PICKUP)).to eq 0
      end
    end
    context 'with missing artowrk location' do
      it 'raises an error' do
        expect {
          ShippingHelper.calculate(
            artwork_missing_location,
            Order::SHIP,
            us_shipping
          )
        }.to raise_error do |error|
          expect(error).to be_a(Errors::ValidationError)
          expect(error.code).to eq :missing_artwork_location
          expect(error.data[:artwork_id]).to eq artwork_missing_location[:_id]
        end
      end
    end
    context 'continental us artwork' do
      context 'with domestic address' do
        it 'returns domestic cost' do
          expect(
            ShippingHelper.calculate(
              continental_us_artwork,
              Order::SHIP,
              us_shipping
            )
          ).to eq 100_00
        end
        context 'with nil domestic shipping' do
          it 'raises error' do
            continental_us_artwork[:domestic_shipping_fee_cents] = nil
            expect {
              ShippingHelper.calculate(
                continental_us_artwork,
                Order::SHIP,
                us_shipping
              )
            }.to raise_error do |error|
              expect(error).to be_a(Errors::ValidationError)
              expect(error.code).to eq :missing_domestic_shipping_fee
            end
          end
        end
      end
      context 'with international address' do
        it 'returns international cost' do
          expect(
            ShippingHelper.calculate(
              continental_us_artwork,
              Order::SHIP,
              italy_shipping
            )
          ).to eq 500_00
        end
        context 'with nil domestic shipping' do
          it 'raises error' do
            continental_us_artwork[:international_shipping_fee_cents] = nil
            expect {
              ShippingHelper.calculate(
                continental_us_artwork,
                Order::SHIP,
                italy_shipping
              )
            }.to raise_error do |error|
              expect(error).to be_a(Errors::ValidationError)
              expect(error.code).to eq :unsupported_shipping_location
            end
          end
        end
      end
    end

    context 'artwork in italy' do
      context 'with domestic address' do
        it 'returns domestic cost' do
          expect(
            ShippingHelper.calculate(
              artwork_in_italy,
              Order::SHIP,
              italy_shipping
            )
          ).to eq 100_00
        end
        context 'with nil domestic shipping' do
          it 'raises error' do
            artwork_in_italy[:domestic_shipping_fee_cents] = nil
            expect {
              ShippingHelper.calculate(
                artwork_in_italy,
                Order::SHIP,
                italy_shipping
              )
            }.to raise_error do |error|
              expect(error).to be_a(Errors::ValidationError)
              expect(error.code).to eq :missing_domestic_shipping_fee
            end
          end
        end
      end
      context 'with international address' do
        it 'returns international cost' do
          expect(
            ShippingHelper.calculate(artwork_in_italy, Order::SHIP, us_shipping)
          ).to eq 500_00
        end
        context 'with nil domestic shipping' do
          it 'raises error' do
            artwork_in_italy[:international_shipping_fee_cents] = nil
            expect {
              ShippingHelper.calculate(
                artwork_in_italy,
                Order::SHIP,
                us_shipping
              )
            }.to raise_error do |error|
              expect(error).to be_a(Errors::ValidationError)
              expect(error.code).to eq :unsupported_shipping_location
            end
          end
        end
      end
    end
  end
end
