# Note that these messages are not what triggers
# reminder emails. The current use case for these is
# giving admins reminders
class ReminderFollowUpJob < ApplicationJob
  queue_as :default

  def perform(order_id, state)
    order = Order.find(order_id)
    return unless order.state == state && Time.now <= order.state_expires_at

    case state
    when Order::SUBMITTED
      OrderEvent.post(order, Order::REMINDER_EVENT_VERB[:pending_approval], nil)
    when Order::APPROVED
      OrderEvent.post(
        order,
        Order::REMINDER_EVENT_VERB[:pending_fulfillment],
        nil
      )
    end
  end
end
