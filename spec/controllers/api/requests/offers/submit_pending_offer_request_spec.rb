require 'rails_helper'
require 'support/gravity_helper'

describe Api::GraphqlController, type: :request do
  describe 'submit order with offer' do
    include_context 'GraphQL Client'

    let(:seller_id) { jwt_partner_ids.first }
    let(:buyer_id) { jwt_user_id }
    let(:artwork) { gravity_v1_artwork(_id: 'a-1', current_version_id: '1') }
    let(:line_item_artwork_version) { artwork[:current_version_id] }
    let(:credit_card_id) { 'grav_c_id1' }
    let(:credit_card) do
      {
        external_id: 'cc-1',
        customer_account: { external_id: 'cus-1' },
        deactivated_at: nil
      }
    end
    let(:line_item) do
      Fabricate(
        :line_item,
        order: order,
        list_price_cents: 2000_00,
        artwork_id: artwork[:_id],
        artwork_version_id: line_item_artwork_version,
        quantity: 2
      )
    end
    let(:order_state) { Order::SUBMITTED }
    let(:order) do
      Fabricate(
        :order,
        mode: Order::OFFER,
        state: order_state,
        seller_id: seller_id,
        seller_type: 'gallery',
        buyer_id: buyer_id,
        credit_card_id: credit_card_id,
        shipping_name: 'Fname Lname',
        shipping_address_line1: '12 Vanak St',
        shipping_address_line2: 'P 80',
        shipping_city: 'Tehran',
        shipping_postal_code: '02198',
        buyer_phone_number: '00123456',
        shipping_country: 'IR',
        fulfillment_type: Order::SHIP,
        items_total_cents: 1000_00,
        buyer_total_cents: 1000_00
      )
    end
    let(:current_offer) do
      Fabricate(
        :offer,
        order: order,
        from_id: seller_id,
        from_type: 'gallery',
        amount_cents: 300
      )
    end
    let(:counter_offer) do
      Fabricate(
        :offer,
        order: order,
        from_id: buyer_id,
        from_type: Order::USER,
        amount_cents: 350,
        tax_total_cents: 10,
        shipping_total_cents: 15,
        responds_to: current_offer
      )
    end
    let(:mutation) do
      <<-GRAPHQL
        mutation($input: SubmitPendingOfferInput!) {
          submitPendingOffer(input: $input) {
            orderOrError {
              ... on OrderWithMutationSuccess {
                order {
                  id
                  state
                  ... on OfferOrder {
                    lastOffer {
                      id
                      submittedAt
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

    let(:mutation_input) { { input: { offerId: counter_offer.id.to_s } } }

    before do
      order.line_items << line_item
      order.update!(last_offer: current_offer)
    end

    describe 'mutation is rejected' do
      it 'if the offer from_id does not match the current user id' do
        counter_offer.update!(from_id: 'random-user-id-on-another-order')

        response = client.execute(mutation, mutation_input)
        expect(
          response.data.submit_pending_offer.order_or_error
        ).not_to respond_to(:order)
        expect(
          response.data.submit_pending_offer.order_or_error.error.code
        ).to eq 'not_found'
        expect(
          response.data.submit_pending_offer.order_or_error.error.type
        ).to eq 'validation'
      end

      it 'if the offer has already been submitted' do
        allow(Gravity).to receive(:get_artwork).with(artwork[:_id]).and_return(
          artwork
        )
        allow(Gravity).to receive(:get_credit_card).with(credit_card_id)
          .and_return(credit_card)
        counter_offer.update!(submitted_at: Time.now.utc)

        response = client.execute(mutation, mutation_input)
        expect(
          response.data.submit_pending_offer.order_or_error
        ).not_to respond_to(:order)
        expect(
          response.data.submit_pending_offer.order_or_error.error.code
        ).to eq 'invalid_offer'
        expect(
          response.data.submit_pending_offer.order_or_error.error.type
        ).to eq 'validation'
      end
    end

    describe 'successful mutations' do
      before do
        allow(Gravity).to receive(:get_artwork).with(artwork[:_id]).and_return(
          artwork
        )
        allow(Gravity).to receive(:get_credit_card).with(credit_card_id)
          .and_return(credit_card)
        allow(Adapters::GravityV1).to receive(:get).with(
          "/partner/#{seller_id}/all"
        )
          .and_return(gravity_v1_partner)
        allow(Adapters::GravityV1).to receive(:get).with(
          "/artwork/#{line_item.artwork_id}"
        )
          .and_return(artwork)
      end

      it 'submits the order and updates submitted_at on the offer' do
        response = client.execute(mutation, mutation_input)
        expect(
          response.data.submit_pending_offer.order_or_error
        ).not_to respond_to(:error)
        expect(counter_offer.reload.submitted_at).not_to be_nil
        expect(order.reload.last_offer).to eq counter_offer
      end
    end
  end
end
