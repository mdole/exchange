class OfferRespondReminderJob < ApplicationJob
  queue_as :default

  def perform(order_id, offer_id)
    order = Order.find(order_id)
    offer = Offer.find(offer_id)
    unless order.state == Order::SUBMITTED &&
           Time.now <= order.state_expires_at &&
           order.last_offer.id == offer_id
      return
    end

    OfferEvent.post(offer, OfferEvent::PENDING_RESPONSE, nil)
  end
end
