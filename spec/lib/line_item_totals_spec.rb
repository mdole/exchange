require 'rails_helper'
require 'support/gravity_helper'

describe LineItemTotals do
  let(:fulfillment_type) { Order::PICKUP }
  let(:artwork) { gravity_v1_artwork }
  let(:shipping_address) { nil }
  let(:seller_locations) { [] }
  let(:artsy_collects_sales_tax) { true }
  let(:order) do
    Fabricate(
      :order,
      seller_id: 'partner-1',
      seller_type: 'gallery',
      buyer_id: 'buyer1',
      buyer_type: Order::USER,
      fulfillment_type: fulfillment_type
    )
  end
  let(:line_item) { Fabricate(:line_item, order: order, artwork_id: 'a-1') }
  let(:line_item_totals) do
    LineItemTotals.new(
      line_item,
      fulfillment_type: fulfillment_type,
      shipping_address: shipping_address,
      seller_locations: seller_locations,
      artsy_collects_sales_tax: artsy_collects_sales_tax
    )
  end
  let(:mock_tax_calculation) do
    allow(Tax::CalculatorService).to receive(:new).and_return(
      double(sales_tax: 100, artsy_should_remit_taxes?: false)
    )
  end
  before do
    allow(Adapters::GravityV1).to receive(:get).with('/artwork/a-1').and_return(
      artwork
    )
  end

  describe 'shipping_total_cents' do
    context 'artwork missing location' do
      let(:artwork) { gravity_v1_artwork(location: nil) }
      it 'raises error' do
        expect { line_item_totals.shipping_total_cents }.to raise_error(
          Errors::ValidationError
        )
      end
    end

    it 'returns nil if missing shipping info' do
      order.update!(fulfillment_type: nil)
      expect(line_item_totals.shipping_total_cents).to eq nil
    end

    context 'PICKUP' do
      it 'returns 0' do
        expect(line_item_totals.shipping_total_cents).to eq 0
      end
    end

    context 'SHIP' do
      let(:fulfillment_type) { Order::SHIP }
      before do
        order.update!(
          shipping_name: 'a',
          shipping_address_line1: 'line1',
          shipping_city: 'city',
          shipping_country: 'US',
          buyer_phone_number: '12312'
        )
        allow(ShippingHelper).to receive(:calculate).and_return(100)
      end

      it 'returns 100' do
        expect(line_item_totals.shipping_total_cents).to eq 100
      end
      it 'returns shipping total * quantity' do
        line_item.update!(quantity: 3)
        expect(line_item_totals.shipping_total_cents).to eq 300
      end
    end
  end

  describe 'tax_total_cents' do
    it 'returns 100' do
      mock_tax_calculation
      expect(line_item_totals.tax_total_cents).to eq 100
    end

    context 'SHIP' do
      let(:fulfillment_type) { Order::SHIP }
      it 'returns nil when missing shipping info' do
        expect(line_item_totals.tax_total_cents).to eq nil
      end
    end
  end

  describe 'should_remit_sales_tax' do
    it 'returns 100' do
      mock_tax_calculation
      expect(line_item_totals.should_remit_sales_tax).to eq false
    end

    context 'SHIP' do
      let(:fulfillment_type) { Order::SHIP }
      it 'returns nil when missing shipping info' do
        expect(line_item_totals.tax_total_cents).to eq nil
      end
    end
  end
end
