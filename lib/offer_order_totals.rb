class OfferOrderTotals
  # Given an offer, it calculate totals on the order
  attr_reader :offer
  delegate :tax_total_cents, to: :offer
  delegate :should_remit_sales_tax, to: :offer
  delegate :commission_rate, to: :order
  delegate :shipping_total_cents, to: :offer
  delegate :tax_total_cents, to: :offer
  delegate :buyer_total_cents, to: :offer

  def initialize(offer)
    @offer = offer
    @order = offer.order
  end

  def items_total_cents
    offer.amount_cents
  end

  def commission_rate
    @commission_rate ||= @order.partner[:effective_commission_rate]
  end

  def commission_fee_cents
    @commission_fee_cents ||= commission_rate * offer.amount_cents
  end

  def transaction_fee_cents
    @transaction_fee_cents ||=
      TransactionFeeCalculator.calculate(buyer_total_cents)
  end

  def seller_total_cents
    unless buyer_total_cents && commission_fee_cents && transaction_fee_cents
      return
    end

    @seller_total_cents ||=
      buyer_total_cents - commission_fee_cents - transaction_fee_cents -
        calculate_remittable_sales_tax
  end

  private

  def calculate_remittable_sales_tax
    @offer.should_remit_sales_tax? ? @offer.tax_total_cents : 0
  end
end
