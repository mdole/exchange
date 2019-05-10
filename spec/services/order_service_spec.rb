require 'rails_helper'
require 'support/gravity_helper'

describe OrderService, type: :services do
  include_context 'use stripe mock'
  let(:state) { Order::PENDING }
  let(:state_reason) { state == Order::CANCELED ? 'seller_lapsed' : nil }
  let(:order) do
    Fabricate(
      :order,
      external_charge_id: captured_charge.id,
      state: state,
      state_reason: state_reason,
      buyer_id: 'b123'
    )
  end
  let!(:line_items) do
    [
      Fabricate(
        :line_item,
        order: order, artwork_id: 'a-1', list_price_cents: 123_00
      ),
      Fabricate(
        :line_item,
        order: order,
        artwork_id: 'a-2',
        edition_set_id: 'es-1',
        quantity: 2,
        list_price_cents: 124_00
      )
    ]
  end
  let(:user_id) { 'user-id' }

  describe 'create_with_artwork' do
    let(:buyer_id) { 'buyer_id' }
    let(:seller_id) { 'seller_id' }
    let(:artwork_id) { 'artwork_id' }
    let(:edition_set_id) { 'edition-set-id' }
    let(:order_mode) { Order::OFFER }

    context 'find_active_or_create=true' do
      let(:call_service) do
        OrderService.create_with_artwork!(
          buyer_id: buyer_id,
          buyer_type: Order::USER,
          mode: order_mode,
          quantity: 2,
          artwork_id: artwork_id,
          edition_set_id: edition_set_id,
          user_agent: 'ua',
          user_ip: '0.1',
          find_active_or_create: true
        )
      end

      context 'with existing order with same artwork/editionset/mode/quantity' do
        before do
          @existing_order =
            Fabricate(
              :order,
              buyer_id: buyer_id,
              buyer_type: Order::USER,
              seller_id: seller_id,
              seller_type: 'Gallery',
              mode: order_mode
            )
          @line_item =
            Fabricate(
              :line_item,
              order: @existing_order,
              artwork_id: artwork_id,
              edition_set_id: edition_set_id,
              quantity: 2
            )
        end

        it 'returns existing order' do
          expect { expect(call_service).to eq @existing_order }.not_to change(
                          Order,
                          :count
                        )
        end

        it 'does not call statsd' do
          expect(Exchange).not_to receive(:dogstatsd)
          call_service
        end

        it 'wont queue OrderFollowUpJob' do
          call_service
          expect(OrderFollowUpJob).not_to have_been_enqueued
        end
      end
      context 'without existing order with same artwork/editionset/mode/quantity' do
        before do
          expect(Adapters::GravityV1).to receive(:get).with(
            "/artwork/#{artwork_id}"
          )
            .once
            .and_return(gravity_v1_artwork)
        end

        it 'creates new order' do
          expect {
            order = call_service
            expect(order.mode).to eq order_mode
            expect(order.buyer_id).to eq buyer_id
            expect(order.seller_id).to eq 'gravity-partner-id'
            expect(order.line_items.count).to eq 1
            expect(
              order.line_items.pluck(:artwork_id, :edition_set_id, :quantity)
                .first
            ).to eq [artwork_id, edition_set_id, 2]
          }.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
        end

        it 'reports to statsd' do
          expect(Exchange).to receive_message_chain(:dogstatsd, :increment)
            .with('order.create')
          call_service
        end

        it 'queues OrderFollowUpJob' do
          call_service
          expect(OrderFollowUpJob).to have_been_enqueued
        end
      end
    end

    context 'find_active_or_create=false' do
      let(:call_service) do
        OrderService.create_with_artwork!(
          buyer_id: buyer_id,
          buyer_type: Order::USER,
          mode: order_mode,
          quantity: 2,
          artwork_id: artwork_id,
          edition_set_id: edition_set_id,
          user_agent: 'ua',
          user_ip: '0.1',
          find_active_or_create: false
        )
      end
      before do
        expect(Adapters::GravityV1).to receive(:get).with(
          "/artwork/#{artwork_id}"
        )
          .once
          .and_return(gravity_v1_artwork)
      end

      context 'with existing order with same artwork/editionset/mode/quantity' do
        before do
          @existing_order =
            Fabricate(
              :order,
              buyer_id: buyer_id,
              buyer_type: Order::USER,
              seller_id: seller_id,
              seller_type: 'Gallery',
              mode: order_mode
            )
          @line_item =
            Fabricate(
              :line_item,
              order: @existing_order,
              artwork_id: artwork_id,
              edition_set_id: edition_set_id,
              quantity: 2
            )
        end

        it 'creates new order' do
          expect {
            order = call_service
            expect(order.mode).to eq order_mode
            expect(order.buyer_id).to eq buyer_id
            expect(order.seller_id).to eq 'gravity-partner-id'
            expect(order.line_items.count).to eq 1
            expect(
              order.line_items.pluck(:artwork_id, :edition_set_id, :quantity)
                .first
            ).to eq [artwork_id, edition_set_id, 2]
          }.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
        end
      end

      context 'without existing order with same artwork/editionset/mode/quantity' do
        it 'creates new order' do
          expect {
            order = call_service
            expect(order.mode).to eq order_mode
            expect(order.buyer_id).to eq buyer_id
            expect(order.seller_id).to eq 'gravity-partner-id'
            expect(order.line_items.count).to eq 1
            expect(
              order.line_items.pluck(:artwork_id, :edition_set_id, :quantity)
                .first
            ).to eq [artwork_id, edition_set_id, 2]
          }.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
        end

        it 'reports to statsd' do
          expect(Exchange).to receive_message_chain(:dogstatsd, :increment)
            .with('order.create')
          call_service
        end

        it 'queues OrderFollowUpJob' do
          call_service
          expect(OrderFollowUpJob).to have_been_enqueued
        end
      end
    end
  end

  describe 'set_payment!' do
    let(:credit_card_id) { 'gravity-cc-1' }
    context 'order in pending state' do
      let(:state) { Order::PENDING }

      context "with a credit card id for the buyer's credit card" do
        let(:credit_card) { { id: credit_card_id, user: { _id: 'b123' } } }

        it 'sets credit_card_id on the order' do
          expect(Gravity).to receive(:get_credit_card).with(credit_card_id)
            .and_return(credit_card)
          OrderService.set_payment!(order, credit_card_id)
          expect(order.reload.credit_card_id).to eq 'gravity-cc-1'
        end
      end

      context 'with a credit card id for credit card not belonging to the buyer' do
        let(:invalid_credit_card) do
          { id: credit_card_id, user: { _id: 'b456' } }
        end

        it 'raises an error' do
          expect(Gravity).to receive(:get_credit_card).with(credit_card_id)
            .and_return(invalid_credit_card)
          expect {
            OrderService.set_payment!(order, credit_card_id)
          }.to raise_error do |error|
            expect(error).to be_a Errors::ValidationError
            expect(error.code).to eq :invalid_credit_card
          end
        end
      end
    end
  end

  describe 'fulfill_at_once!' do
    let(:fulfillment_params) do
      {
        courier: 'usps',
        tracking_id: 'track_this_id',
        estimated_delivery: 10.days.from_now
      }
    end

    context 'with order in approved state' do
      let(:state) { Order::APPROVED }

      it 'changes order state to fulfilled' do
        OrderService.fulfill_at_once!(order, fulfillment_params, user_id)
        expect(order.reload.state).to eq Order::FULFILLED
      end

      it 'creates one fulfillment model' do
        Timecop.freeze do
          expect {
            OrderService.fulfill_at_once!(order, fulfillment_params, user_id)
          }.to change(Fulfillment, :count).by(1)
          fulfillment = Fulfillment.last
          expect(fulfillment.courier).to eq 'usps'
          expect(fulfillment.tracking_id).to eq 'track_this_id'
          expect(fulfillment.estimated_delivery.to_date).to eq 10.days.from_now
               .to_date
        end
      end

      it 'sets all line items fulfillment to one fulfillment' do
        OrderService.fulfill_at_once!(order, fulfillment_params, user_id)
        fulfillment = Fulfillment.last
        line_items.each do |li|
          expect(li.fulfillments.first.id).to eq fulfillment.id
        end
      end

      it 'queues job to post fulfillment event' do
        OrderService.fulfill_at_once!(order, fulfillment_params, user_id)
        expect(PostEventJob).to have_been_enqueued.with(
          'commerce',
          kind_of(String),
          'order.fulfilled'
        )
      end
    end

    Order::STATES.reject { |s| s == Order::APPROVED }.each do |state|
      context "order in #{state}" do
        let(:state) { state }
        it 'raises error' do
          expect {
            OrderService.fulfill_at_once!(order, fulfillment_params, user_id)
          }.to raise_error do |error|
            expect(error).to be_a Errors::ValidationError
            expect(error.code).to eq :invalid_state
          end
        end

        it 'does not add fulfillments' do
          expect {
            OrderService.fulfill_at_once!(order, fulfillment_params, user_id)
          }.to raise_error(Errors::ValidationError).and change(
                                                     Fulfillment,
                                                     :count
                                                   )
                                                     .by(0)
        end
      end
    end
  end

  describe 'abandon!' do
    context 'order in pending state' do
      let(:state) { Order::PENDING }
      it 'abandons the order' do
        OrderService.abandon!(order)
        expect(order.reload.state).to eq Order::ABANDONED
      end

      it 'updates state_update_at' do
        Timecop.freeze do
          order.update!(state_updated_at: 10.days.ago)
          OrderService.abandon!(order)
          expect(order.reload.state_updated_at.to_date).to eq Time.now.utc
               .to_date
        end
      end

      it 'creates state history' do
        expect { OrderService.abandon!(order) }.to change(
          order.state_histories,
          :count
        )
          .by(1)
      end
    end

    Order::STATES.reject { |s| s == Order::PENDING }.each do |state|
      context "order in #{state}" do
        let(:state) { state }
        it 'does not change state' do
          expect { OrderService.abandon!(order) }.to raise_error(
            Errors::ValidationError
          )
          expect(order.reload.state).to eq state
        end

        it 'raises error' do
          expect { OrderService.abandon!(order) }.to raise_error do |error|
            expect(error).to be_a Errors::ValidationError
            expect(error.type).to eq :validation
            expect(error.code).to eq :invalid_state
            expect(error.data).to match(state: state)
          end
        end
      end
    end
  end
end
