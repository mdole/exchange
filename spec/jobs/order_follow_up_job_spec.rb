require 'rails_helper'

describe OrderFollowUpJob, type: :job do
  let(:state) { Order::PENDING }
  let(:order) { Fabricate(:order, state: state) }
  describe '#perform' do
    context 'with an order in the same state after its expiration time' do
      context 'expired PENDING' do
        it 'transitions to abandoned' do
          Timecop.freeze(order.state_expires_at + 1.second) do
            expect(OrderService).to receive(:abandon!).with(order)
            OrderFollowUpJob.perform_now(order.id, Order::PENDING)
          end
        end
      end
      context 'expired SUBMITTED' do
        let(:state) { Order::SUBMITTED }
        let(:seller_type) { Order::PARTNER }
        let(:buyer_type) { Order::USER }
        let(:seller_id) { 'partner_id' }
        let(:buyer_id) { 'user_id' }
        let(:mode) { Order::BUY }
        let(:order) do
          Fabricate(
            :order,
            mode: mode,
            state: state,
            buyer_id: buyer_id,
            seller_id: seller_id,
            seller_type: seller_type,
            buyer_type: buyer_type
          )
        end
        context 'Buy order' do
          it 'transitions a submitted order to seller_lapsed' do
            Timecop.freeze(order.state_expires_at + 1.second) do
              expect_any_instance_of(OrderCancellationService).to receive(
                :seller_lapse!
              )
              OrderFollowUpJob.perform_now(order.id, Order::SUBMITTED)
            end
          end
        end
        context 'Offer order' do
          let(:mode) { Order::OFFER }
          let(:offer) do
            Fabricate(
              :offer,
              from_id: seller_id,
              order: order,
              from_type: seller_type,
              submitted_at: Time.now.utc
            )
          end
          before { order.update!(last_offer: offer) }
          context 'Last offer from seller (awaiting response from buyer)' do
            it 'transitions a submitted order to buyer_lapsed' do
              Timecop.freeze(order.state_expires_at + 1.second) do
                expect_any_instance_of(OrderCancellationService).to receive(
                  :buyer_lapse!
                )
                OrderFollowUpJob.perform_now(order.id, Order::SUBMITTED)
              end
            end
          end
          context 'Last offer from buyer (awaiting response from seller)' do
            let(:offer) do
              Fabricate(
                :offer,
                from_id: buyer_id,
                order: order,
                from_type: buyer_type,
                submitted_at: Time.now.utc
              )
            end
            it 'transitions a submitted order to seller_lapsed' do
              Timecop.freeze(order.state_expires_at + 1.second) do
                expect_any_instance_of(OrderCancellationService).to receive(
                  :seller_lapse!
                )
                OrderFollowUpJob.perform_now(order.id, Order::SUBMITTED)
              end
            end
          end
        end
      end
      context 'expired APPROVED' do
        let(:state) { Order::APPROVED }
        it 'posts an event' do
          Timecop.freeze(order.state_expires_at + 1.second) do
            expect(OrderEvent).to receive(:post).with(order, 'unfulfilled', nil)
            OrderFollowUpJob.perform_now(order.id, Order::APPROVED)
          end
        end
      end
    end
    context 'with an order in a different state than when the job was made' do
      it 'does nothing' do
        order.update!(state: Order::SUBMITTED)
        Timecop.freeze(order.state_expires_at + 1.second) do
          expect(OrderService).to_not receive(:abandon!)
          expect_any_instance_of(OrderCancellationService).to_not receive(
                                                                    :seller_lapse!
                                                                  )
          OrderFollowUpJob.perform_now(order.id, Order::PENDING)
        end
      end
    end
    context 'with an order in the same state before its expiration time' do
      it 'does nothing' do
        expect(OrderService).to_not receive(:abandon!)
        expect_any_instance_of(OrderCancellationService).to_not receive(
                                                                  :seller_lapse!
                                                                )
        OrderFollowUpJob.perform_now(order.id, Order::PENDING)
      end
    end
  end
end
