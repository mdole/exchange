class OrderApproveService
  attr_reader :order

  def initialize(order, user_id)
    @order = order
    @user_id = user_id
    @transaction = nil
  end

  def process!
    unless @order.payment_method == Order::CREDIT_CARD
      raise Errors::ValidationError.new(
              :unsupported_payment_method,
              @order.payment_method
            )
    end

    @order.approve! do
      @transaction =
        PaymentService.capture_authorized_charge(@order.external_charge_id)
      if @transaction.failed?
        raise Errors::ProcessingError.new(
                :capture_failed,
                @transaction.failure_data
              )
      end
    end
    post_process
  ensure
    @order.transactions << @transaction if @transaction.present?
  end

  private

  def post_process
    record_stats
    @order.line_items.each { |li| RecordSalesTaxJob.perform_later(li.id) }
    OrderEvent.delay_post(@order, Order::APPROVED, @user_id)
    OrderFollowUpJob.set(wait_until: @order.state_expires_at).perform_later(
      @order.id,
      @order.state
    )
    ReminderFollowUpJob.set(wait_until: @order.state_expiration_reminder_time)
      .perform_later(@order.id, @order.state)
  end

  def record_stats
    Exchange.dogstatsd.increment 'order.approve'
    Exchange.dogstatsd.count('order.money_collected', @order.buyer_total_cents)
    Exchange.dogstatsd.count(
      'order.commission_collected',
      @order.commission_fee_cents
    )
  end
end
