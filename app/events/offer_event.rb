class OfferEvent < Events::BaseEvent
  TOPIC = 'commerce'.freeze
  ACTIONS = [
    SUBMITTED = 'submitted'.freeze,
    PENDING_RESPONSE = 'pending_response'.freeze
  ].freeze

  def self.post(offer, action, user_id)
    event = new(user: user_id, action: action, model: offer)
    Artsy::EventService.post_event(topic: TOPIC, event: event)
  end

  def self.delay_post(offer, action)
    event = new(user: offer.creator_id, action: action, model: offer)
    PostEventJob.perform_later(TOPIC, event.to_json, event.routing_key)
  end

  def subject
    { id: @subject }
  end

  def properties
    {
      id: @object.id,
      amount_cents: @object.amount_cents,
      submitted_at: @object.submitted_at,
      from_participant: @object.from_participant,
      last_offer: @object.last_offer?,
      from_id: @object.from_id,
      from_type: @object.from_type,
      creator_id: @object.creator_id,
      in_response_to: in_response_to,
      note: @object.note,
      shipping_total_cents: @object.shipping_total_cents,
      tax_total_cents: @object.tax_total_cents,
      order: order
    }
  end

  private

  def order
    order = @object.order
    OrderEvent::PROPERTIES_ATTRS.map { |att| [att, order.send(att)] }.to_h
      .merge(line_items: line_items_details)
  end

  def line_items_details
    @object.order.line_items.map { |li| line_item_detail(li) }
  end

  def line_item_detail(line_item)
    {
      price_cents: line_item.list_price_cents,
      list_price_cents: line_item.list_price_cents,
      artwork_id: line_item.artwork_id,
      edition_set_id: line_item.edition_set_id,
      quantity: line_item.quantity,
      commission_fee_cents: line_item.commission_fee_cents
    }
  end

  def in_response_to
    return if @object.responds_to.blank?

    {
      id: @object.responds_to.id,
      amount_cents: @object.responds_to.amount_cents,
      created_at: @object.responds_to.created_at,
      from_participant: @object.responds_to.from_participant
    }
  end
end
