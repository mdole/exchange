class StripeWebhookService
  PROCESSED_EVENT_TYPES = %w[charge.refunded charge.failed].freeze

  def initialize(event)
    @event = event
  end

  def process!
    case @event.type
    when 'charge.refunded'
      process_refund_event
    else
      Rails.logger.debug(
        "ignore event #{@event[:id]} with type: #{@event[:type]}"
      )
    end
  end

  private

  def process_refund_event
    order = Order.find_by(external_charge_id: @event.data.object.id)
    unless order
      raise Errors::ProcessingError.new(
              :unknown_event_charge,
              event_id: @event.id, charge_id: @event.data.object.id
            )
    end
    return if order.state == Order::REFUNDED # ignore if it's already refunded
    unless @event.data.object.refunded
      raise Errors::ProcessingError.new(
              :received_partial_refund,
              event_id: @event.id, charge_id: @event.data.object.id
            )
    end

    order.refund! do
      order.transactions.create!(
        external_id: @event.id,
        destination_id: @event.data.object.destination_id,
        source_id: @event.data.object.source.id,
        amount_cents: @event.data.object.amount,
        status: Transaction::SUCCESS,
        transaction_type: Transaction::REFUND
      )
    end
    order.line_items.each { |li| Gravity.undeduct_inventory(li) }
  end
end
