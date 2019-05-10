require 'rails_helper'
require 'support/gravity_helper'

describe OrderShipping, type: :services do
  let(:buyer_id) { 'user_id' }
  let(:seller_id) { 'partner-1' }
  let(:artwork_id) { 'artwork-id' }
  let(:order) do
    Fabricate(
      :order,
      buyer_id: buyer_id,
      buyer_type: Order::USER,
      seller_id: seller_id,
      seller_type: 'gallery'
    )
  end
  let(:line_item) do
    Fabricate(
      :line_item,
      order: order, list_price_cents: 500, quantity: 2, artwork_id: artwork_id
    )
  end
  let(:order_shipping) { OrderShipping.new(order) }
  before do
    line_item
    allow(Adapters::GravityV1).to receive(:get).with(
      "/partner/#{seller_id}/all"
    )
      .and_return(gravity_v1_partner)
    allow(Adapters::GravityV1).to receive(:get).with(
      "/partner/#{seller_id}/locations",
      params: { private: true, address_type: ['Business', 'Sales tax nexus'] }
    )
      .and_return([{ country: 'US', state: 'NY' }])
    allow(Adapters::GravityV1).to receive(:get).with("/artwork/#{artwork_id}")
      .and_return(gravity_v1_artwork(_id: artwork_id))
  end
  describe '#pickup!' do
    context 'Buy Order' do
      before do
        allow_any_instance_of(Tax::CalculatorService).to receive_messages(
          sales_tax: 100, artsy_should_remit_taxes?: false
        )
        order_shipping.pickup!
      end
      it 'sets pickup fulfillment type' do
        expect(order.fulfillment_type).to eq Order::PICKUP
      end
      it 'sets shipping to 0' do
        expect(order.shipping_total_cents).to eq 0
      end
      it 'updates line items' do
        expect(line_item.reload.sales_tax_cents).to eq 100
        expect(line_item.should_remit_sales_tax).to eq false
      end
      it 'updates totals on the order' do
        expect(order.tax_total_cents).to eq 100
        expect(order.buyer_total_cents).to eq 1_100
      end
    end
    context 'Offer Order' do
      context 'with pending offer' do
      end
      context 'without pending offer' do
      end
    end
  end

  describe '#ship' do
    context 'Buy Order' do
    end
    context 'Offer Order' do
      context 'with pending offer' do
      end
      context 'without pending offer' do
      end
    end
  end
end
