require 'rails_helper'
require 'timecop'

describe ReminderFollowUpJob, type: :job do
  let(:state) { Order::PENDING }
  let(:state_expires_at) { 1.day.from_now }
  let(:order) do
    Fabricate(:order, state: state, state_expires_at: state_expires_at)
  end
  describe '#perform' do
    context 'with an order in the same state before its expiration time' do
      context 'SUBMITTED' do
        let(:state) { Order::SUBMITTED }
        it 'sends an internal message to admins about seller lapsing' do
          expect(OrderEvent).to receive(:post).with(
            order,
            Order::REMINDER_EVENT_VERB[:pending_approval],
            nil
          )

          ReminderFollowUpJob.perform_now(order.id, Order::SUBMITTED)
        end
      end
      context 'APPROVED' do
        let(:state) { Order::APPROVED }
        it 'sends an internal message to admins about buyer lapsing' do
          expect(OrderEvent).to receive(:post).with(
            order,
            Order::REMINDER_EVENT_VERB[:pending_fulfillment],
            nil
          )

          ReminderFollowUpJob.perform_now(order.id, Order::APPROVED)
        end
      end
    end
    context 'with an order in a different state than when the job was made' do
      it 'does nothing' do
        order.update!(state: Order::SUBMITTED)
        expect(OrderEvent).to_not receive(:post)

        ReminderFollowUpJob.perform_now(order.id, Order::PENDING)
      end
    end
    context 'with an order in the same state after its expiration time' do
      it 'does nothing' do
        order.update!(state_expires_at: 1.hour.ago)
        expect(OrderEvent).to_not receive(:post)
        ReminderFollowUpJob.perform_now(order.id, Order::PENDING)
      end
    end
  end
end
