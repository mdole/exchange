module TransactionFeeCalculator
  def self.calculate(total_charge_amount)
    0 unless total_charge_amount&.positive?

    # This is based on Stripe US fee, it will be different for other countries https://stripe.com/us/pricing
    (Money.new(total_charge_amount * 2.9 / 100, 'USD') + Money.new(30, 'USD'))
      .cents
  end
end
