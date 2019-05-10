require 'rails_helper'
require 'support/gravity_helper'
require 'support/use_stripe_mock'

describe Api::GraphqlController, type: :request do
  include_context 'use stripe mock'
  describe 'submit_order mutation' do
    include_context 'GraphQL Client'
    let(:seller_id) { jwt_partner_ids.first }
    let(:partner) { gravity_v1_partner(effective_commission_rate: 0.1) }
    let(:user_id) { jwt_user_id }
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
        seller_id: seller_id,
        buyer_id: user_id,
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
    let(:artwork) { gravity_v1_artwork(_id: 'a-1', current_version_id: '1') }
    let(:line_item) do
      Fabricate(
        :line_item,
        order: order,
        list_price_cents: 1000_00,
        artwork_id: 'a-1',
        artwork_version_id: '1'
      )
    end

    let(:mutation) do
      <<-GRAPHQL
        mutation($input: SubmitOrderInput!) {
          submitOrder(input: $input) {
            orderOrError {
              ... on OrderWithMutationSuccess {
                order {
                  id
                  state
                  commissionFeeCents
                  buyer {
                    ... on Partner {
                      id
                    }
                  }
                  seller {
                    ... on User {
                      id
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

    let(:submit_order_input) { { input: { id: order.id.to_s } } }

    before { order.line_items << line_item }

    context 'user without permission to this order' do
      let(:user_id) { 'random-user-id-on-another-order' }
      it 'returns permission error' do
        response = client.execute(mutation, submit_order_input)
        expect(response.data.submit_order.order_or_error).not_to respond_to(
                                                                   :order
                                                                 )
        expect(response.data.submit_order.order_or_error.error).not_to be_nil
        expect(
          response.data.submit_order.order_or_error.error.code
        ).to eq 'not_found'
        expect(
          response.data.submit_order.order_or_error.error.type
        ).to eq 'validation'
        expect(order.reload.state).to eq Order::PENDING
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
          .with(query: { partner_id: seller_id })
          .to_return(status: 200, body: [merchant_account].to_json)
      end
      let(:partner_account_request) do
        stub_request(
          :get,
          "#{Rails.application.config_for(:gravity)['api_v1_root']}/partner/#{
            seller_id
          }/all"
        )
          .to_return(status: 200, body: gravity_v1_partner.to_json)
      end

      context 'with order without shipping info' do
        before { order.update_attributes! shipping_country: nil }
        it 'returns error' do
          allow(Gravity).to receive(:get_artwork).and_return(artwork)
          response = client.execute(mutation, submit_order_input)
          expect(response.data.submit_order.order_or_error).not_to respond_to(
                                                                     :order
                                                                   )
          expect(
            response.data.submit_order.order_or_error.error.code
          ).to eq 'missing_required_info'
          expect(
            response.data.submit_order.order_or_error.error.type
          ).to eq 'validation'
          expect(order.reload.state).to eq Order::PENDING
        end
      end

      context 'with order without credit card id' do
        let(:credit_card_id) { nil }
        it 'returns error' do
          allow(Gravity).to receive(:get_artwork).and_return(artwork)
          response = client.execute(mutation, submit_order_input)
          expect(response.data.submit_order.order_or_error).not_to respond_to(
                                                                     :order
                                                                   )
          expect(
            response.data.submit_order.order_or_error.error.code
          ).to eq 'missing_required_info'
          expect(
            response.data.submit_order.order_or_error.error.type
          ).to eq 'validation'
          expect(order.reload.state).to eq Order::PENDING
        end
      end

      context 'with order in non-pending state' do
        before { order.update_attributes! state: Order::APPROVED }
        it 'returns error' do
          allow(Gravity).to receive(:get_artwork).and_return(artwork)
          allow(Gravity).to receive(:get_merchant_account).and_return(
            merchant_account
          )
          allow(Gravity).to receive(:get_credit_card).and_return(credit_card)
          allow(Gravity).to receive(:fetch_partner).and_return(partner)
          response = client.execute(mutation, submit_order_input)
          expect(response.data.submit_order.order_or_error).not_to respond_to(
                                                                     :order
                                                                   )
          expect(
            response.data.submit_order.order_or_error.error.code
          ).to eq 'invalid_state'
          expect(
            response.data.submit_order.order_or_error.error.type
          ).to eq 'validation'
          expect(order.reload.state).to eq Order::APPROVED
        end
      end

      context 'with artwork version mismatch' do
        let(:artwork) do
          gravity_v1_artwork(_id: 'a-1', current_version_id: '2')
        end
        before { allow(Gravity).to receive(:get_artwork).and_return(artwork) }
        it 'raises processing error' do
          expect(Gravity).not_to receive(:deduct_inventory)
          expect(Gravity).not_to receive(:get_merchant_account)
          expect(Gravity).not_to receive(:get_credit_card)
          expect(Adapters::GravityV1).not_to receive(:get).with(
                                               "/partner/#{seller_id}/all"
                                             )
          response = client.execute(mutation, submit_order_input)
          expect(response.data.submit_order.order_or_error).not_to respond_to(
                                                                     :order
                                                                   )
          expect(
            response.data.submit_order.order_or_error.error.code
          ).to eq 'artwork_version_mismatch'
          expect(
            response.data.submit_order.order_or_error.error.type
          ).to eq 'processing'
          expect(order.reload.state).to eq Order::PENDING
        end
      end

      context 'with failed stripe charge' do
        before do
          deduct_inventory_request
          merchant_account_request
          credit_card_request
          artwork_request
          partner_account_request
          undeduct_inventory_request
          StripeMock.prepare_card_error(:card_declined)
        end

        it 'raises processing error' do
          response = client.execute(mutation, submit_order_input)
          expect(
            response.data.submit_order.order_or_error.error.code
          ).to eq 'charge_authorization_failed'
        end

        it 'stores failed transaction' do
          expect { client.execute(mutation, submit_order_input) }.to change(
            order.transactions.where(status: Transaction::FAILURE),
            :count
          )
            .by(1)
          expect(order.reload.external_charge_id).to be_nil
          expect(order.transactions.last.failed?).to be true
        end

        it 'undeducts inventory' do
          client.execute(mutation, submit_order_input)
          expect(undeduct_inventory_request).to have_been_requested
        end
      end

      it 'submits the order' do
        deduct_inventory_request
        merchant_account_request
        credit_card_request
        artwork_request
        partner_account_request
        response = client.execute(mutation, submit_order_input)
        expect(deduct_inventory_request).to have_been_requested

        expect(response.data.submit_order.order_or_error).to respond_to(:order)
        expect(response.data.submit_order.order_or_error.order).not_to be_nil

        response_order = response.data.submit_order.order_or_error.order
        expect(response_order.id).to eq order.id.to_s
        expect(response_order.state).to eq 'SUBMITTED'
        expect(response_order.commission_fee_cents).to eq 800_00

        expect(response.data.submit_order.order_or_error).not_to respond_to(
                                                                   :error
                                                                 )
        expect(order.reload.state).to eq Order::SUBMITTED
        expect(order.commission_fee_cents).to eq 800_00
        expect(order.state_updated_at).not_to be_nil
        expect(order.state_expires_at).to eq(order.state_updated_at + 2.days)
        expect(order.reload.transactions.last.external_id).not_to be_nil
        expect(
          order.reload.transactions.last.transaction_type
        ).to eq Transaction::HOLD
      end
    end
  end
end
