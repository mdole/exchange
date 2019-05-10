require 'rails_helper'
require 'support/use_stripe_mock'
require 'support/gravity_helper'

describe Api::GraphqlController, type: :request do
  describe 'buyer_counter_offer mutation' do
    include_context 'GraphQL Client'
    let(:order_seller_id) { jwt_partner_ids.first }
    let(:buyer_id) { jwt_user_id }
    let(:artwork_location) { { country: 'US' } }
    let(:artwork) do
      {
        _id: 'a-1',
        current_version_id: '1',
        location: artwork_location,
        domestic_shipping_fee_cents: 1_000
      }
    end
    let(:order_state) { Order::SUBMITTED }
    let!(:order) do
      Fabricate(
        :order,
        mode: Order::OFFER,
        state: order_state,
        seller_id: order_seller_id,
        buyer_id: buyer_id,
        items_total_cents: 421,
        **shipping_info
      )
    end
    let!(:seller_offer) do
      Fabricate(
        :offer,
        order: order,
        amount_cents: 10_000,
        from_id: order_seller_id,
        from_type: 'gallery',
        submitted_at: Time.now.utc
      )
    end
    let(:line_item_artwork_version) { artwork[:current_version_id] }
    let!(:line_item) do
      Fabricate(
        :line_item,
        order: order,
        list_price_cents: 2000_00,
        artwork_id: artwork[:_id],
        artwork_version_id: line_item_artwork_version,
        quantity: 2
      )
    end
    let(:partner_address) do
      Address.new(
        street_line1: '401 Broadway',
        country: 'US',
        city: 'New York',
        region: 'NY',
        postal_code: '10013'
      )
    end
    let(:shipping_info) do
      {
        shipping_name: 'Fname Lname',
        shipping_address_line1: '12 Vanak St',
        shipping_address_line2: 'P 80',
        shipping_city: 'New York',
        shipping_postal_code: '02198',
        buyer_phone_number: '00123456',
        shipping_region: 'NY',
        shipping_country: 'US',
        fulfillment_type: Order::SHIP
      }
    end
    let(:taxjar_client) { double }
    let(:tax_response) { double(amount_to_collect: 3.00) }

    let(:mutation) do
      <<-GRAPHQL
        mutation($input: BuyerCounterOfferInput!) {
          buyerCounterOffer(input: $input) {
            orderOrError {
              ... on OrderWithMutationSuccess {
                order {
                  id
                  state
                  ... on OfferOrder {
                    myLastOffer {
                      id
                      amountCents
                      respondsTo {
                        id
                      }
                    }
                  }
                }
              }
              ... on OrderWithMutationFailure {
                error {
                  code
                  data
                  type
                }
              }
            }
          }
        }
      GRAPHQL
    end

    let(:buyer_counter_offer_input) do
      { input: { offerId: seller_offer.id.to_s, amountCents: 10_000 } }
    end

    before do
      order.update!(last_offer: seller_offer)

      allow(Gravity).to receive(:fetch_partner_locations).with(
        order_seller_id,
        tax_only: true
      )
        .and_return([partner_address])
      allow(Gravity).to receive(:get_artwork).and_return(artwork)
      allow(Taxjar::Client).to receive(:new).with(
        api_key: Rails.application.config_for(:taxjar)['taxjar_api_key'],
        api_url: nil
      )
        .and_return(taxjar_client)
      allow(taxjar_client).to receive(:tax_for_order).with(any_args).and_return(
        tax_response
      )
    end

    context 'when not in the submitted state' do
      let(:order_state) { Order::PENDING }

      it "returns invalid state transition error and doesn't change the order state" do
        response = client.execute(mutation, buyer_counter_offer_input)

        expect(
          response.data.buyer_counter_offer.order_or_error.error.type
        ).to eq 'validation'
        expect(
          response.data.buyer_counter_offer.order_or_error.error.code
        ).to eq 'invalid_state'
        expect(order.reload.state).to eq Order::PENDING
      end
    end

    context 'when attempting to counter not-the-last-offer' do
      it 'returns a validation error and does not change the order state' do
        create_another_offer(
          from_id: order.seller_id, from_type: order.seller_type
        )
        response = client.execute(mutation, buyer_counter_offer_input)
        expect(
          response.data.buyer_counter_offer.order_or_error.error.type
        ).to eq 'validation'
        expect(
          response.data.buyer_counter_offer.order_or_error.error.code
        ).to eq 'not_last_offer'
        expect(order.reload.state).to eq Order::SUBMITTED
      end
    end

    context 'with user without permission to order' do
      let(:buyer_id) { 'another-user-id' }

      it 'returns permission error' do
        response = client.execute(mutation, buyer_counter_offer_input)

        expect(
          response.data.buyer_counter_offer.order_or_error.error.type
        ).to eq 'validation'
        expect(
          response.data.buyer_counter_offer.order_or_error.error.code
        ).to eq 'not_found'
        expect(order.reload.state).to eq Order::SUBMITTED
      end
    end

    context 'when the specified offer does not exist' do
      let(:buyer_counter_offer_input) do
        { input: { offerId: '-1', amountCents: 20_000 } }
      end

      it 'returns a not-found error' do
        expect {
          client.execute(mutation, buyer_counter_offer_input)
        }.to raise_error do |error|
          expect(error.status_code).to eq(404)
        end
      end
    end

    context 'when not waiting for buyer response' do
      before do
        seller_offer.update!(
          from_id: order.buyer_id, from_type: order.buyer_type
        )
      end
      it 'returns cannot_counter' do
        response = client.execute(mutation, buyer_counter_offer_input)

        expect(
          response.data.buyer_counter_offer.order_or_error.error.type
        ).to eq 'validation'
        expect(
          response.data.buyer_counter_offer.order_or_error.error.code
        ).to eq 'cannot_counter'
      end
    end

    context 'with proper permission' do
      before do
        allow(Adapters::GravityV1).to receive(:get).with(
          "/partner/#{order_seller_id}/all"
        )
          .and_return(gravity_v1_partner)
      end
      it 'counters the order' do
        expect {
          client.execute(mutation, buyer_counter_offer_input)
          last_pending_offer =
            order.offers.where(from_id: jwt_user_id).order(created_at: :desc)
              .first
          expect(last_pending_offer.responds_to).to eq(seller_offer)
          expect(last_pending_offer.amount_cents).to eq(10_000)
          expect(last_pending_offer.tax_total_cents).to eq(300)
          expect(last_pending_offer.should_remit_sales_tax).to eq(false)
          expect(last_pending_offer.amount_cents).to eq(10_000)
          expect(last_pending_offer.submitted_at).to eq(nil)
          expect(last_pending_offer.creator_id).to eq(jwt_user_id)
          expect(last_pending_offer.from_id).to eq(jwt_user_id)
          expect(last_pending_offer.from_type).to eq(Order::USER)
          # shouldn't update order amounts until offer is submitted
          expect(order.reload.items_total_cents).to eq(421)
        }.to change { order.reload.offers.count }.from(1).to(2)
      end
      context 'with offer note' do
        let(:note) { "I'll double my offer." }
        let(:buyer_counter_offer_input) do
          {
            input: {
              offerId: seller_offer.id.to_s, amountCents: 10_000, note: note
            }
          }
        end
        it 'counters the order with note' do
          client.execute(mutation, buyer_counter_offer_input)
          last_pending_offer =
            order.offers.where(from_id: jwt_user_id).order(created_at: :desc)
              .first
          expect(last_pending_offer.note).to eq(note)
        end
      end
    end
  end

  def create_another_offer(from_id:, from_type:)
    another_offer =
      Fabricate(:offer, order: order, from_id: from_id, from_type: from_type)
    order.update!(last_offer: another_offer)
  end
end
