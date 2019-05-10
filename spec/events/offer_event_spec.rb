require 'rails_helper'

describe OfferEvent, type: :events do
  before { Timecop.freeze(Time.parse('2018-08-16 15:48:00 -0400')) }
  after { Timecop.return }

  let(:seller_id) { 'partner-1' }
  let(:user_id) { 'user-1' }
  let(:shipping_info) do
    {
      fulfillment_type: Order::SHIP,
      shipping_name: 'Fname Lname',
      shipping_address_line1: '123 Main St',
      shipping_address_line2: 'Apt 2',
      shipping_city: 'Chicago',
      shipping_country: 'USA',
      shipping_postal_code: '60618',
      shipping_region: 'IL'
    }
  end
  let(:order) do
    Fabricate(
      :order,
      buyer_id: user_id,
      buyer_type: Order::USER,
      buyer_phone_number: '00123459876',
      seller_id: 'partner-1',
      seller_type: 'gallery',
      currency_code: 'usd',
      mode: Order::OFFER,
      shipping_total_cents: 50,
      tax_total_cents: 30,
      items_total_cents: 300,
      buyer_total_cents: 380,
      state: 'submitted',
      **shipping_info
    )
  end
  let!(:line_item1) do
    Fabricate(
      :line_item,
      list_price_cents: 200, order: order, commission_fee_cents: 40
    )
  end
  let(:old_offer) do
    Fabricate(
      :offer,
      order: order,
      from_id: order.seller_id,
      from_type: 'gallery',
      amount_cents: 240
    )
  end
  let(:offer) do
    Fabricate(
      :offer,
      order: order,
      from_id: order.buyer_id,
      from_type: Order::USER,
      submitted_at: Time.now.utc,
      amount_cents: 120,
      responds_to: old_offer,
      note: 'Please consider my reasonable offer.'
    )
  end

  let(:expected_line_item_properties) do
    [
      {
        price_cents: 200,
        list_price_cents: 200,
        artwork_id: line_item1.artwork_id,
        edition_set_id: line_item1.edition_set_id,
        quantity: 1,
        commission_fee_cents: 40
      }
    ]
  end
  let(:event) do
    OfferEvent.new(user: user_id, action: OfferEvent::SUBMITTED, model: offer)
  end

  describe 'post' do
    it 'calls ArtsyEventService to post event' do
      expect(Artsy::EventService).to receive(:post_event).with(
        topic: 'commerce', event: instance_of(OfferEvent)
      )
      OfferEvent.post(offer, OfferEvent::SUBMITTED, user_id)
    end
  end

  describe '#subject' do
    it 'returns user id' do
      expect(event.subject[:id]).to eq user_id
    end
  end

  describe '#object' do
    it 'returns order id' do
      expect(event.object[:id]).to eq offer.id.to_s
    end
  end

  describe '#properties' do
    it 'includes expected offer properties' do
      expect(event.properties[:id]).to eq offer.id
      expect(event.properties[:submitted_at]).not_to be_nil
      expect(event.properties[:from_participant]).to eq Order::BUYER
      expect(event.properties[:from_id]).to eq offer.from_id
      expect(event.properties[:from_type]).to eq offer.from_type
      expect(event.properties[:creator_id]).to eq offer.creator_id
      expect(event.properties[:shipping_total_cents]).to eq offer
           .shipping_total_cents
      expect(event.properties[:tax_total_cents]).to eq offer.tax_total_cents
      expect(
        event.properties[:note]
      ).to eq 'Please consider my reasonable offer.'
    end
    it 'includes in_response_to' do
      in_response_to = event.properties[:in_response_to]
      expect(in_response_to).not_to be_nil
      expect(in_response_to[:id]).to eq old_offer.id
      expect(in_response_to[:amount_cents]).to eq 240
    end
    describe '#order' do
      context 'without last_offer' do
        it 'returns correct properties for a submitted order' do
          properties = event.properties
          order_prop = properties[:order]
          expect(order_prop[:id]).to eq order.id
          expect(order_prop[:mode]).to eq Order::OFFER
          expect(order_prop[:code]).to eq order.code
          expect(order_prop[:currency_code]).to eq 'USD'
          expect(order_prop[:state]).to eq 'submitted'
          expect(order_prop[:buyer_id]).to eq user_id
          expect(order_prop[:buyer_type]).to eq Order::USER
          expect(order_prop[:fulfillment_type]).to eq Order::SHIP
          expect(order_prop[:seller_id]).to eq seller_id
          expect(order_prop[:seller_type]).to eq 'gallery'
          expect(order_prop[:items_total_cents]).to eq 300
          expect(order_prop[:shipping_total_cents]).to eq 50
          expect(order_prop[:tax_total_cents]).to eq 30
          expect(order_prop[:buyer_total_cents]).to eq 380
          expect(order_prop[:updated_at]).not_to be_nil
          expect(order_prop[:created_at]).not_to be_nil
          expect(order_prop[:line_items].count).to eq 1
          expect(order_prop[:line_items]).to match_array(
            expected_line_item_properties
          )
          expect(order_prop[:shipping_name]).to eq 'Fname Lname'
          expect(order_prop[:shipping_address_line1]).to eq '123 Main St'
          expect(order_prop[:shipping_address_line2]).to eq 'Apt 2'
          expect(order_prop[:shipping_city]).to eq 'Chicago'
          expect(order_prop[:shipping_country]).to eq 'USA'
          expect(order_prop[:shipping_postal_code]).to eq '60618'
          expect(order_prop[:buyer_phone_number]).to eq '00123459876'
          expect(order_prop[:shipping_region]).to eq 'IL'
          expect(order_prop[:state_expires_at]).to eq Time.parse(
               '2018-08-18 15:48:00 -0400'
             )
          expect(order_prop[:total_list_price_cents]).to eq(200)
        end
      end
    end
  end
end
