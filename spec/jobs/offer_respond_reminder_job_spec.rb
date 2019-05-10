require 'rails_helper'
require 'timecop'

describe OfferRespondReminderJob, type: :job do
  let(:state) { Order::SUBMITTED }
  let(:state_expires_at) { 1.day.from_now }
  let(:offer_submitted_at) { 7.days.ago }
  let(:order) do
    Fabricate(:order, state: state, state_expires_at: state_expires_at)
  end
  let(:offer) { Fabricate(:offer, order: order) }
  describe '#perform' do
    context 'order is not in submitted state' do
      context Order::CANCELED do
        it 'does not send a reminder' do
          order.update! state: Order::CANCELED, state_reason: 'buyer_lapsed'
          expect(OfferEvent).to_not receive(:post)
          OfferRespondReminderJob.perform_now(order.id, offer.id)
        end
      end
      (Order::STATES - [Order::SUBMITTED, Order::CANCELED]).each do |bad_state|
        context bad_state do
          it 'does not send a reminder' do
            order.update! state: bad_state
            expect(OfferEvent).to_not receive(:post)

            OfferRespondReminderJob.perform_now(order.id, offer.id)
          end
        end
      end
    end
    context 'order is in submitted state' do
      before { order.update! last_offer: offer }
      it 'sends a reminder for a submitted order if the offer is still pending' do
        expect(OfferEvent).to receive(:post).with(
          offer,
          OfferEvent::PENDING_RESPONSE,
          nil
        )

        OfferRespondReminderJob.perform_now(order.id, offer.id)
      end
      it 'does not send a reminder if the offer is not the last offer' do
        new_offer = Fabricate(:offer, order: order)
        order.update! last_offer: new_offer
        expect(OfferEvent).to_not receive(:post)

        OfferRespondReminderJob.perform_now(order.id, offer.id)
      end

      context 'state is expired' do
        let(:state_expires_at) { 1.hour.ago }
        it 'does not send a reminder' do
          order.update! state_expires_at: state_expires_at
          expect(OfferEvent).to_not receive(:post)

          OfferRespondReminderJob.perform_now(order.id, offer.id)
        end
      end
    end
  end
end
