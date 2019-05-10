require 'rails_helper'
require 'support/use_stripe_mock'

describe Api::GraphqlController, type: :request do
  include_context 'use stripe mock'
  describe 'seller_accept_offer mutation' do
    include_context 'GraphQL Client'
    let(:partner) { { effective_commission_rate: 0.1 } }
    let(:order_seller_id) { jwt_partner_ids.first }
    let(:order_buyer_id) { jwt_user_id }
    let(:order_state) { Order::SUBMITTED }
    let(:credit_card_id) { 'cc-1' }
    let(:merchant_account) { { external_id: 'ma-1' } }
    let(:credit_card) do
      {
        external_id: stripe_customer.default_source,
        customer_account: { external_id: stripe_customer.id }
      }
    end
    let(:order) do
      Fabricate(
        :order,
        state: order_state,
        seller_id: order_seller_id,
        buyer_id: order_buyer_id,
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
        seller_type: 'gallery',
        buyer_type: 'user'
      )
    end
    let!(:line_item) do
      Fabricate(
        :line_item,
        order: order,
        list_price_cents: 1000_00,
        artwork_id: 'a-1',
        artwork_version_id: '1'
      )
    end
    let(:offer) do
      Fabricate(
        :offer,
        order: order,
        from_id: order_buyer_id,
        from_type: 'user',
        amount_cents: 800_00,
        shipping_total_cents: 100_00,
        tax_total_cents: 300_00
      )
    end
    let(:artwork) { { _id: 'a-1', current_version_id: '1' } }

    let(:mutation) do
      <<-GRAPHQL
        mutation($input: SellerAcceptOfferInput!) {
          sellerAcceptOffer(input: $input) {
            orderOrError {
              ... on OrderWithMutationSuccess {
                order {
                  id
                  state
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

    let(:seller_accept_offer_input) { { input: { offerId: offer.id.to_s } } }

    before do
      order.update!(
        last_offer: offer,
        buyer_total_cents: offer.buyer_total_cents,
        shipping_total_cents: offer.shipping_total_cents
      )
    end

    context 'when not in the submitted state' do
      let(:order_state) { Order::PENDING }

      it "returns invalid state transition error and doesn't change the order state" do
        mock_pre_process_calls

        response = client.execute(mutation, seller_accept_offer_input)

        expect(
          response.data.seller_accept_offer.order_or_error.error.type
        ).to eq 'validation'
        expect(
          response.data.seller_accept_offer.order_or_error.error.code
        ).to eq 'invalid_state'
        expect(order.reload.state).to eq Order::PENDING
      end
    end

    context 'when attempting to accept not the last offer' do
      it 'returns a validation error and does not change the order state' do
        mock_pre_process_calls

        create_order_and_original_offer
        create_another_offer

        response = client.execute(mutation, seller_accept_offer_input)

        expect(
          response.data.seller_accept_offer.order_or_error.error.type
        ).to eq 'validation'
        expect(
          response.data.seller_accept_offer.order_or_error.error.code
        ).to eq 'not_last_offer'
        expect(order.reload.state).to eq Order::SUBMITTED
      end
    end

    context 'with user without permission to this partner' do
      let(:order_seller_id) { 'another-partner-id' }

      it 'returns permission error' do
        response = client.execute(mutation, seller_accept_offer_input)

        expect(
          response.data.seller_accept_offer.order_or_error.error.type
        ).to eq 'validation'
        expect(
          response.data.seller_accept_offer.order_or_error.error.code
        ).to eq 'not_found'
        expect(order.reload.state).to eq Order::SUBMITTED
      end
    end

    context 'offer from seller' do
      let(:offer) do
        Fabricate(
          :offer,
          order: order, from_id: order_seller_id, from_type: 'gallery'
        )
      end

      it 'returns permission error' do
        response = client.execute(mutation, seller_accept_offer_input)

        expect(
          response.data.seller_accept_offer.order_or_error.error.type
        ).to eq 'validation'
        expect(
          response.data.seller_accept_offer.order_or_error.error.code
        ).to eq 'cannot_accept_offer'
        expect(order.reload.state).to eq Order::SUBMITTED
      end
    end

    context 'when the specified offer does not exist' do
      let(:seller_accept_offer_input) { { input: { offerId: '-1' } } }

      it 'returns a not-found error' do
        expect {
          client.execute(mutation, seller_accept_offer_input)
        }.to raise_error do |error|
          expect(error.status_code).to eq(404)
        end
      end
    end

    context 'with proper permission' do
      let(:deduct_inventory_request) do
        stub_request(
          :put,
          "#{
            Rails.application.config_for(:gravity)['api_v1_root']
          }/artwork/a-1/inventory"
        )
          .with(body: { deduct: 1 })
          .to_return(status: 200, body: {}.to_json)
      end
      let(:undeduct_inventory_request) do
        stub_request(
          :put,
          "#{
            Rails.application.config_for(:gravity)['api_v1_root']
          }/artwork/a-1/inventory"
        )
          .with(body: { undeduct: 1 })
          .to_return(status: 200, body: {}.to_json)
      end
      let(:credit_card_request) do
        stub_request(
          :get,
          "#{
            Rails.application.config_for(:gravity)['api_v1_root']
          }/credit_card/#{credit_card_id}"
        )
          .to_return(status: 200, body: credit_card.to_json)
      end
      let(:artwork_request) do
        stub_request(
          :get,
          "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-1"
        )
          .to_return(status: 200, body: artwork.to_json)
      end
      let(:merchant_account_request) do
        stub_request(
          :get,
          "#{
            Rails.application.config_for(:gravity)['api_v1_root']
          }/merchant_accounts"
        )
          .with(query: { partner_id: order_seller_id })
          .to_return(status: 200, body: [merchant_account].to_json)
      end
      let(:partner_account_request) do
        stub_request(
          :get,
          "#{Rails.application.config_for(:gravity)['api_v1_root']}/partner/#{
            order_seller_id
          }/all"
        )
          .to_return(status: 200, body: gravity_v1_partner.to_json)
      end
      before do
        deduct_inventory_request
        merchant_account_request
        credit_card_request
        artwork_request
        partner_account_request
      end

      context 'with failed stripe charge' do
        before do
          undeduct_inventory_request
          StripeMock.prepare_card_error(:card_declined)
        end

        it 'raises processing error' do
          response = client.execute(mutation, seller_accept_offer_input)
          expect(
            response.data.seller_accept_offer.order_or_error.error.code
          ).to eq 'capture_failed'
        end

        it 'stores failed transaction' do
          expect {
            client.execute(mutation, seller_accept_offer_input)
          }.to change(
            order.transactions.where(status: Transaction::FAILURE),
            :count
          )
            .by(1)
          expect(order.reload.external_charge_id).to be_nil
          expect(order.transactions.last.failed?).to be true
          expect(order.last_transaction_failed?).to be true
        end

        it 'undeducts inventory' do
          client.execute(mutation, seller_accept_offer_input)
          expect(undeduct_inventory_request).to have_been_requested
        end
      end

      it 'approves the order' do
        response = client.execute(mutation, seller_accept_offer_input)

        expect(deduct_inventory_request).to have_been_requested

        expect(response.data.seller_accept_offer.order_or_error).to respond_to(
          :order
        )
        expect(
          response.data.seller_accept_offer.order_or_error.order
        ).not_to be_nil

        response_order = response.data.seller_accept_offer.order_or_error.order
        expect(response_order.id).to eq order.id.to_s
        expect(response_order.state).to eq Order::APPROVED.upcase

        expect(
          response.data.seller_accept_offer.order_or_error
        ).not_to respond_to(:error)
        expect(order.reload.state).to eq Order::APPROVED
        expect(order.state_updated_at).not_to be_nil
        expect(order.state_expires_at).to eq(order.state_updated_at + 7.days)
        expect(order.reload.transactions.last.external_id).not_to be_nil
        expect(
          order.reload.transactions.last.transaction_type
        ).to eq Transaction::CAPTURE
      end
    end
  end

  def create_order_and_original_offer
    order
    offer
  end

  def create_another_offer
    another_offer = Fabricate(:offer, order: order)
    order.update!(last_offer: another_offer)
  end

  def mock_pre_process_calls
    allow(Gravity).to receive(:get_artwork).and_return(artwork)
    allow(Gravity).to receive(:get_merchant_account).and_return(
      merchant_account
    )
    allow(Gravity).to receive(:get_credit_card).and_return(credit_card)
    allow(Gravity).to receive(:fetch_partner).and_return(partner)
  end
end
