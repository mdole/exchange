require 'rails_helper'
require 'support/use_stripe_mock'

RSpec.shared_examples 'rejecting an offer' do
  before { order.update!(last_offer: offer) }

  context 'when not in the submitted state' do
    let(:order_state) { Order::PENDING }

    it "returns invalid state transition error and doesn't change the order state" do
      response = client.execute(mutation, input)
      expect(
        response.data.response.order_or_error.error.type
      ).to eq 'validation'
      expect(
        response.data.response.order_or_error.error.code
      ).to eq 'invalid_state'
      expect(order.reload.state).to eq Order::PENDING
    end
  end

  context 'when attempting to reject not the last offer' do
    it 'returns a validation error and does not change the order state' do
      create_order_and_original_offer
      create_another_offer

      response = client.execute(mutation, input)

      expect(
        response.data.response.order_or_error.error.type
      ).to eq 'validation'
      expect(
        response.data.response.order_or_error.error.code
      ).to eq 'not_last_offer'
      expect(order.reload.state).to eq Order::SUBMITTED
    end
  end

  context 'when the specified offer does not exist' do
    let(:input) { { input: { offerId: '-1', rejectReason: reject_reason } } }

    it 'returns a not-found error' do
      expect { client.execute(mutation, input) }.to raise_error do |error|
        expect(error.status_code).to eq(404)
      end
    end
  end

  context 'with proper permission' do
    it 'rejects the order' do
      expect(OrderEvent).to receive(:delay_post).with(
        order,
        Order::CANCELED,
        'user-id'
      )
      expect { client.execute(mutation, input) }.to change {
        order.reload.state
      }.from(Order::SUBMITTED)
        .to(Order::CANCELED)
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
end

describe Api::GraphqlController, type: :request do
  include_context 'GraphQL Client'

  let(:seller_id) { jwt_partner_ids.first }
  let(:buyer_id) { jwt_user_id }
  let(:order_state) { Order::SUBMITTED }
  let(:reject_reason) { 'SELLER_REJECTED_OFFER_TOO_LOW' }
  let(:order) do
    Fabricate(
      :order,
      mode: 'offer',
      state: order_state,
      seller_id: seller_id,
      seller_type: 'gallery',
      buyer_id: buyer_id
    )
  end
  let(:offer) do
    Fabricate(:offer, order: order, from_id: buyer_id, from_type: Order::USER)
  end

  describe 'seller_reject_order mutation' do
    let(:buyer_id) { 'buyer-id' }
    let(:seller_mutation) do
      <<-GRAPHQL
        mutation($input: SellerRejectOfferInput!) {
          response: sellerRejectOffer(input: $input) {
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
    let(:seller_input) do
      { input: { offerId: offer.id.to_s, rejectReason: reject_reason } }
    end
    it_behaves_like 'rejecting an offer' do
      let(:mutation) { seller_mutation }
      let(:input) { seller_input }
    end

    before { order.update!(last_offer: offer) }

    context 'with user without permission to this partner' do
      let(:seller_id) { 'another-partner-id' }

      it 'returns permission error' do
        response = client.execute(seller_mutation, seller_input)

        expect(
          response.data.response.order_or_error.error.type
        ).to eq 'validation'
        expect(
          response.data.response.order_or_error.error.code
        ).to eq 'not_found'
        expect(order.reload.state).to eq Order::SUBMITTED
      end
    end

    context 'with offer created by seller' do
      let(:offer) do
        Fabricate(
          :offer,
          order: order, from_id: seller_id, from_type: 'gallery'
        )
      end

      it 'returns validation error and does not change the order state' do
        response = client.execute(seller_mutation, seller_input)

        expect(
          response.data.response.order_or_error.error.type
        ).to eq 'validation'
        expect(
          response.data.response.order_or_error.error.code
        ).to eq 'cannot_reject_offer'
        expect(order.reload.state).to eq Order::SUBMITTED
      end
    end

    context 'with an offer that is not the last_offer' do
      let(:another_offer) { Fabricate(:offer, order: order) }

      before do
        # last_offer is set in Orders::InitialOffer. "Stubbing" out the
        # dependent behavior of this class to by setting last_offer directly
        order.update!(last_offer: another_offer)
      end

      it 'raises a validation error' do
        response = client.execute(seller_mutation, seller_input)
        expect(
          response.data.response.order_or_error.error.type
        ).to eq 'validation'
        expect(
          response.data.response.order_or_error.error.code
        ).to eq 'not_last_offer'
        expect(order.reload.state).to eq Order::SUBMITTED
      end
    end
  end

  describe 'buyer_reject_order mutation' do
    let(:buyer_mutation) do
      <<-GRAPHQL
          mutation($input: BuyerRejectOfferInput!) {
            response: buyerRejectOffer(input: $input) {
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
    let(:buyer_input) { { input: { offerId: offer.id.to_s } } }
    let(:offer) do
      Fabricate(:offer, order: order, from_id: seller_id, from_type: 'gallery')
    end

    it_behaves_like 'rejecting an offer' do
      let(:mutation) { buyer_mutation }
      let(:input) { buyer_input }
    end

    before { order.update!(last_offer: offer) }

    context 'with offer created by buyer' do
      let(:offer) do
        Fabricate(
          :offer,
          order: order, from_id: buyer_id, from_type: Order::USER
        )
      end

      it 'returns validation error and does not change the order state' do
        response = client.execute(buyer_mutation, buyer_input)

        expect(
          response.data.response.order_or_error.error.type
        ).to eq 'validation'
        expect(
          response.data.response.order_or_error.error.code
        ).to eq 'cannot_reject_offer'
        expect(order.reload.state).to eq Order::SUBMITTED
      end
    end

    context 'when no rejection reason is provided' do
      let(:reject_reason) { nil }
      it 'sets a generic rejection reason' do
        order.update!(last_offer: offer)
        expect { client.execute(buyer_mutation, buyer_input) }.to change {
          order.reload.state
        }.from(Order::SUBMITTED)
          .to(Order::CANCELED)

        expect(order.state_reason).to eq Order::REASONS[Order::CANCELED][
             :buyer_rejected
           ]
      end
    end

    context 'with an offer that is not the last_offer' do
      let(:another_offer) { Fabricate(:offer, order: order) }

      before do
        # last_offer is set in Orders::InitialOffer. "Stubbing" out the
        # dependent behavior of this class to by setting last_offer directly
        order.update!(last_offer: another_offer)
      end

      it 'raises a validation error' do
        response = client.execute(buyer_mutation, buyer_input)

        expect(
          response.data.response.order_or_error.error.type
        ).to eq 'validation'
        expect(
          response.data.response.order_or_error.error.code
        ).to eq 'not_last_offer'
        expect(order.reload.state).to eq Order::SUBMITTED
      end
    end
  end
end
