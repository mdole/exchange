module OrderService
  def self.create_with_artwork!(
    buyer_id:,
    buyer_type:,
    mode:,
    quantity:,
    artwork_id:,
    edition_set_id: nil,
    user_agent:,
    user_ip:,
    find_active_or_create: false
  )
    order_creator =
      OrderCreator.new(
        buyer_id: buyer_id,
        buyer_type: buyer_type,
        mode: mode,
        quantity: quantity,
        artwork_id: artwork_id,
        edition_set_id: edition_set_id,
        user_agent: user_agent,
        user_ip: user_ip
      )

    # in case of Offer orders, we want to reuse existing pending/submitted offers
    create_method = find_active_or_create ? :find_or_create! : :create!
    order_creator.send(create_method) do |created_order|
      Exchange.dogstatsd.increment 'order.create'
      OrderFollowUpJob.set(wait_until: created_order.state_expires_at)
        .perform_later(created_order.id, created_order.state)
    end
  end

  def self.set_shipping!(order, fulfillment_type:, shipping:)
    unless order.state == Order::PENDING
      raise Errors::ValidationError, :invalid_state
    end

    order_shipping = OrderShipping.new(order)
    case fulfillment_type
    when Order::PICKUP
      order_shipping.pickup!
    when Order::SHIP
      order_shipping.ship!(shipping)
    end
    order
  end

  def self.set_payment!(order, credit_card_id)
    credit_card = Gravity.get_credit_card(credit_card_id)
    unless credit_card.dig(:user, :_id) == order.buyer_id
      raise Errors::ValidationError.new(
              :invalid_credit_card,
              credit_card_id: credit_card_id
            )
    end

    order.update!(credit_card_id: credit_card_id)
    order
  end

  def self.submit!(order, user_id)
    unless order.valid_artwork_version?
      Exchange.dogstatsd.increment 'submit.artwork_version_mismatch'
      raise Errors::ProcessingError, :artwork_version_mismatch
    end

    order_processor = OrderProcessor.new(order, user_id)
    unless order_processor.valid?
      raise Errors::ValidationError, order_processor.error
    end

    order.submit! do
      order.line_items.each do |li|
        li.update!(commission_fee_cents: li.current_commission_fee_cents)
      end
      totals = BuyOrderTotals.new(order)
      order.update!(
        transaction_fee_cents: totals.transaction_fee_cents,
        commission_rate: order.current_commission_rate,
        commission_fee_cents: totals.commission_fee_cents,
        seller_total_cents: totals.seller_total_cents
      )
      order_processor.hold!
      order.transactions << order_processor.transaction
    end

    OrderEvent.delay_post(order, Order::SUBMITTED, user_id)
    OrderFollowUpJob.set(wait_until: order.state_expires_at).perform_later(
      order.id,
      order.state
    )
    ReminderFollowUpJob.set(wait_until: order.state_expiration_reminder_time)
      .perform_later(order.id, order.state)
    Exchange.dogstatsd.increment 'order.submitted'
    order
  rescue Errors::FailedTransactionError => e
    handle_failed_transaction(e, order, user_id)
    raise e
  end

  def self.fulfill_at_once!(order, fulfillment, user_id)
    order.fulfill! do
      fulfillment =
        Fulfillment.create!(
          fulfillment.slice(:courier, :tracking_id, :estimated_delivery)
        )
      order.line_items.each do |li|
        li.line_item_fulfillments.create!(fulfillment_id: fulfillment.id)
      end
    end
    OrderEvent.delay_post(order, Order::FULFILLED, user_id)
    order
  end

  def self.confirm_pickup!(order, user_id)
    unless order.fulfillment_type == Order::PICKUP
      raise Errors::ValidationError, :wrong_fulfillment_type
    end

    order.fulfill!
    OrderEvent.delay_post(order, Order::FULFILLED, user_id)
    order
  end

  def self.confirm_fulfillment!(order, user_id)
    unless order.fulfillment_type == Order::SHIP
      raise Errors::ValidationError, :wrong_fulfillment_type
    end

    order.fulfill!
    OrderEvent.delay_post(order, Order::FULFILLED, user_id)
    order
  end

  def self.abandon!(order)
    order.abandon!
  end

  class << self
    private

    def handle_failed_transaction(failed_transaction_exception, order, user_id)
      transaction = failed_transaction_exception.transaction
      return if transaction.blank?

      order.transactions << transaction
      PostTransactionNotificationJob.perform_later(
        transaction.id,
        TransactionEvent::CREATED,
        user_id
      )
    end
  end
end
