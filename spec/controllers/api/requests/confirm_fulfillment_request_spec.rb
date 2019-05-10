require 'rails_helper'

describe Api::GraphqlController, type: :request do
  describe 'confirm_fulfillment mutation' do
    include_context 'GraphQL Client'
    let(:seller_id) { jwt_partner_ids.first }
    let(:user_id) { jwt_user_id }
    let(:credit_card_id) { 'cc-1' }
    let(:order) do
      Fabricate(
        :order,
        seller_id: seller_id, buyer_id: user_id, fulfillment_type: Order::SHIP
      )
    end

    let(:mutation) do
      <<-GRAPHQL
        mutation($input: ConfirmFulfillmentInput!) {
          confirmFulfillment(input: $input) {
            orderOrError {
              ... on OrderWithMutationSuccess {
                order {
                  id
                  state
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

    let(:confirm_fulfillment_input) { { input: { id: order.id.to_s } } }

    context 'with user without permission to this partner' do
      let(:seller_id) { 'another-partner-id' }
      it 'returns permission error' do
        response = client.execute(mutation, confirm_fulfillment_input)
        expect(
          response.data.confirm_fulfillment.order_or_error.error.type
        ).to eq 'validation'
        expect(
          response.data.confirm_fulfillment.order_or_error.error.code
        ).to eq 'not_found'
        expect(order.reload.state).to eq Order::PENDING
      end
    end

    context 'with proper permission' do
      Order::STATES.reject do |s|
        [Order::APPROVED, Order::CANCELED].include? s
      end.each do |state|
        context "with order not in #{state} state" do
          before { order.update! state: state }
          it 'returns error' do
            response = client.execute(mutation, confirm_fulfillment_input)
            expect(
              response.data.confirm_fulfillment.order_or_error.error.type
            ).to eq 'validation'
            expect(
              response.data.confirm_fulfillment.order_or_error.error.code
            ).to eq 'invalid_state'
            expect(order.reload.state).to eq state
          end
        end
      end

      context 'order in approved state' do
        before { order.update! state: Order::APPROVED }
        context 'pickup order' do
          before { order.update! fulfillment_type: Order::PICKUP }
          it 'returns error' do
            response = client.execute(mutation, confirm_fulfillment_input)
            expect(
              response.data.confirm_fulfillment.order_or_error.error.type
            ).to eq 'validation'
            expect(
              response.data.confirm_fulfillment.order_or_error.error.code
            ).to eq 'wrong_fulfillment_type'
            expect(order.reload.state).to eq Order::APPROVED
          end
        end

        context 'ship order' do
          it 'approves the order' do
            response = client.execute(mutation, confirm_fulfillment_input)
            expect(
              response.data.confirm_fulfillment.order_or_error.order.id
            ).to eq order.id.to_s
            expect(
              response.data.confirm_fulfillment.order_or_error.order.state
            ).to eq 'FULFILLED'
            expect(
              response.data.confirm_fulfillment.order_or_error
            ).not_to respond_to(:error)
            expect(order.reload.state).to eq Order::FULFILLED
            expect(order.state_expires_at).to be_nil
          end

          it 'queues a job for posting events' do
            client.execute(mutation, confirm_fulfillment_input)
            expect(PostEventJob).to have_been_enqueued.with(
              'commerce',
              kind_of(String),
              'order.fulfilled'
            )
          end
        end
      end
    end
  end
end
