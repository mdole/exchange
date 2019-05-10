module AdminHelper
  def format_money_cents(amount_cents, negate: false)
    return 'N/A' if amount_cents.blank?

    amount_cents *= -1 if negate
    number_to_currency(
      amount_cents.to_f / 100,
      unit: '$', negative_format: '( %u%n )'
    )
  end
end
