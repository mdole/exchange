require 'rails_helper'

describe OrderCancellationService, type: :services do
  include_context 'use stripe mock'
  let(:order_state) { Order::SUBMITTED }
  let(:order_mode) { Order::BUY }
  let(:order) do
    Fabricate(
      :order,
      external_charge_id: captured_charge.id,
      state: order_state,
      mode: order_mode,
      buyer_id: 'buyer',
      buyer_type: Order::USER
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
  let(:service) { OrderCancellationService.new(order, user_id) }

  describe '#reject!' do
    context 'with a successful refund' do
      before { service.reject! }

      it 'queues undeduct inventory job' do
        expect(UndeductLineItemInventoryJob).to have_been_enqueued.with(
          line_items.first.id
        )
      end

      it 'records the transaction' do
        expect(order.transactions.last.external_id).to_not eq nil
        expect(
          order.transactions.last.transaction_type
        ).to eq Transaction::REFUND
        expect(order.transactions.last.status).to eq Transaction::SUCCESS
      end

      it 'updates the order state' do
        expect(order.state).to eq Order::CANCELED
        expect(order.state_reason).to eq Order::REASONS[Order::CANCELED][
             :seller_rejected_other
           ]
      end

      it 'queues notification job' do
        expect(PostEventJob).to have_been_enqueued.with(
          'commerce',
          kind_of(String),
          'order.canceled'
        )
      end
    end

    context 'with an unsuccessful refund' do
      before do
        allow(Stripe::Refund).to receive(:create).with(
          hash_including(charge: captured_charge.id)
        )
          .and_raise(
          Stripe::StripeError.new(
            'too late to refund buddy...',
            json_body: {
              error: { code: 'something', message: 'refund failed' }
            }
          )
        )
        expect { service.reject! }.to raise_error(
          Errors::ProcessingError
        ).and change(order.transactions, :count).by(1)
      end

      it 'raises a ProcessingError and records the transaction' do
        expect(order.transactions.last.external_id).to eq captured_charge.id
        expect(
          order.transactions.last.transaction_type
        ).to eq Transaction::REFUND
        expect(order.transactions.last.status).to eq Transaction::FAILURE
      end

      it 'does not queue undeduct inventory job' do
        expect(UndeductLineItemInventoryJob).not_to have_been_enqueued.with(
                                                      line_items.first.id
                                                    )
      end
    end

    context 'when the order is paid for by wire transfer' do
      it 'raises a ValidationError' do
        order.update!(payment_method: Order::WIRE_TRANSFER)
        expect { service.reject! }.to raise_error do |e|
          expect(e.code).to eq :unsupported_payment_method
        end
      end
    end

    context 'with an offer-mode order' do
      let!(:offer) do
        Fabricate(
          :offer,
          order: order, from_id: order.buyer_id, from_type: order.buyer_type
        )
      end
      let(:service) { OrderCancellationService.new(order, 'seller') }

      before do
        # last_offer is set in Orders::InitialOffer. "Stubbing" out the
        # dependent behavior of this class to by setting last_offer directly
        order.update!(last_offer: offer, mode: 'offer')
      end

      describe 'with a submitted offer' do
        it 'updates the state of the order' do
          expect {
            service.reject!(
              Order::REASONS[Order::CANCELED][:seller_rejected_offer_too_low]
            )
          }.to change { order.state }.from(Order::SUBMITTED).to(
            Order::CANCELED
          ).and change { order.state_reason }.from(nil).to(
                                                                  Order::REASONS[
                                                                    Order::CANCELED
                                                                  ][
                                                                    :seller_rejected_offer_too_low
                                                                  ]
                                                                )
        end

        it 'instruments an rejected offer' do
          dd_statsd = stub_ddstatsd_instance
          expect(dd_statsd).to receive(:increment).with('order.reject')
          service.reject!(
            Order::REASONS[Order::CANCELED][:seller_rejected_offer_too_low]
          )
        end

        it 'sends a notification' do
          expect(PostEventJob).to receive(:perform_later).with(
            'commerce',
            kind_of(String),
            'order.canceled'
          )
          service.reject!(
            Order::REASONS[Order::CANCELED][:seller_rejected_offer_too_low]
          )
        end
      end

      describe "when we can't reject the order" do
        let(:order) { Fabricate(:order, state: Order::PENDING) }
        let(:offer) { Fabricate(:offer, order: order) }

        it "doesn't instrument" do
          dd_statsd = stub_ddstatsd_instance
          allow(dd_statsd).to receive(:increment).with('offer.reject')

          expect {
            service.reject!(
              Order::REASONS[Order::CANCELED][:seller_rejected_offer_too_low]
            )
          }.to raise_error(Errors::ValidationError)

          expect(dd_statsd).to_not have_received(:increment)
        end
      end
    end
  end

  describe '#seller_lapse!' do
    context 'Buy Order' do
      context 'with a successful refund' do
        before { service.seller_lapse! }

        it 'queues undeduct inventory job' do
          expect(UndeductLineItemInventoryJob).to have_been_enqueued.with(
            line_items.first.id
          )
        end

        it 'records the transaction' do
          expect(order.transactions.last.external_id).to_not eq nil
          expect(
            order.transactions.last.transaction_type
          ).to eq Transaction::REFUND
          expect(order.transactions.last.status).to eq Transaction::SUCCESS
        end

        it 'updates the order state' do
          expect(order.state).to eq Order::CANCELED
          expect(order.state_reason).to eq Order::REASONS[Order::CANCELED][
               :seller_lapsed
             ]
        end

        it 'queues notification job' do
          expect(PostEventJob).to have_been_enqueued.with(
            'commerce',
            kind_of(String),
            'order.canceled'
          )
        end
      end

      context 'with an unsuccessful refund' do
        before do
          allow(Stripe::Refund).to receive(:create).with(
            hash_including(charge: captured_charge.id)
          )
            .and_raise(
            Stripe::StripeError.new(
              'too late to refund buddy...',
              json_body: {
                error: { code: 'something', message: 'refund failed' }
              }
            )
          )
          expect { service.reject! }.to raise_error(
            Errors::ProcessingError
          ).and change(order.transactions, :count).by(1)
        end

        it 'raises a ProcessingError and records the transaction' do
          expect(order.transactions.last.external_id).to eq captured_charge.id
          expect(
            order.transactions.last.transaction_type
          ).to eq Transaction::REFUND
          expect(order.transactions.last.status).to eq Transaction::FAILURE
        end

        it 'does not queue undeduct inventory job' do
          expect(UndeductLineItemInventoryJob).not_to have_been_enqueued.with(
                                                        line_items.first.id
                                                      )
        end
      end
    end

    context 'Offer Order' do
      let(:order_mode) { Order::OFFER }
      let!(:line_items) do
        [
          Fabricate(
            :line_item,
            order: order, artwork_id: 'a-1', list_price_cents: 123_00
          )
        ]
      end

      before { service.seller_lapse! }

      it 'updates the order state' do
        expect(order.state).to eq Order::CANCELED
        expect(order.state_reason).to eq Order::REASONS[Order::CANCELED][
             :seller_lapsed
           ]
      end

      it 'queues notification job' do
        expect(PostEventJob).to have_been_enqueued.with(
          'commerce',
          kind_of(String),
          'order.canceled'
        )
      end
    end
  end

  describe '#buyer_lapse!' do
    context 'Offer Order' do
      let(:order_mode) { Order::OFFER }
      let!(:line_items) do
        [
          Fabricate(
            :line_item,
            order: order, artwork_id: 'a-1', list_price_cents: 123_00
          )
        ]
      end

      before { service.buyer_lapse! }

      it 'updates the order state' do
        expect(order.state).to eq Order::CANCELED
        expect(order.state_reason).to eq Order::REASONS[Order::CANCELED][
             :buyer_lapsed
           ]
      end

      it 'queues notification job' do
        expect(PostEventJob).to have_been_enqueued.with(
          'commerce',
          kind_of(String),
          'order.canceled'
        )
      end
    end
  end

  describe '#refund!' do
    [Order::APPROVED, Order::FULFILLED].each do |state|
      context "#{state} order" do
        let(:order_state) { state }

        context 'with a successful refund' do
          before { service.refund! }

          it 'queues undeduct inventory job' do
            expect(UndeductLineItemInventoryJob).to have_been_enqueued.with(
              line_items.first.id
            )
          end

          it 'records the transaction' do
            expect(order.transactions.last.external_id).to_not eq nil
            expect(
              order.transactions.last.transaction_type
            ).to eq Transaction::REFUND
            expect(order.transactions.last.status).to eq Transaction::SUCCESS
          end

          it 'updates the order state' do
            expect(order.state).to eq Order::REFUNDED
          end

          it 'queues notification job' do
            expect(PostEventJob).to have_been_enqueued.with(
              'commerce',
              kind_of(String),
              'order.refunded'
            )
          end
        end

        context 'with an unsuccessful refund' do
          before do
            allow(Stripe::Refund).to receive(:create).with(
              hash_including(charge: captured_charge.id)
            )
              .and_raise(
              Stripe::StripeError.new(
                'too late to refund buddy...',
                json_body: {
                  error: { code: 'something', message: 'refund failed' }
                }
              )
            )
            expect { service.refund! }.to raise_error(
              Errors::ProcessingError
            ).and change(order.transactions, :count).by(1)
          end

          it 'raises a ProcessingError and records the transaction' do
            expect(order.transactions.last.external_id).to eq captured_charge.id
            expect(
              order.transactions.last.transaction_type
            ).to eq Transaction::REFUND
            expect(order.transactions.last.status).to eq Transaction::FAILURE
          end

          it 'does not queue undeduct inventory job' do
            expect(UndeductLineItemInventoryJob).not_to have_been_enqueued.with(
                                                          line_items.first.id
                                                        )
          end
        end

        context 'when the order is paid for by wire transfer' do
          it 'raises a ValidationError' do
            order.update!(payment_method: Order::WIRE_TRANSFER)
            expect { service.refund! }.to raise_error do |e|
              expect(e.code).to eq :unsupported_payment_method
            end
          end
        end
      end
    end
  end

  def stub_ddstatsd_instance
    dd_statsd = double(Datadog::Statsd)
    allow(Exchange).to receive(:dogstatsd).and_return(dd_statsd)

    dd_statsd
  end
end
