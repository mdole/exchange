module OrderHelper
  def valid_artwork_version?
    line_items.all?(&:latest_artwork_version?)
  end

  def assert_credit_card
    case credit_card
    when ->(cc) { cc[:external_id].blank? }
      :credit_card_missing_external_id
    when ->(cc) { cc.dig(:customer_account, :external_id).blank? }
      :credit_card_missing_customer
    when ->(cc) { cc[:deactivated_at].present? }
      :credit_card_deactivated
    end
  end

  def artworks
    @artworks ||= line_items.uniq.map { |li| [li.artwork_id, li.artwork] }.to_h
  end

  def credit_card
    @credit_card ||= Gravity.get_credit_card(credit_card_id)
  end

  def partner
    @partner ||= Gravity.fetch_partner(seller_id)
  end

  def merchant_account
    @merchant_account ||= Gravity.get_merchant_account(seller_id)
  end

  def seller_locations
    @seller_locations ||=
      Gravity.fetch_partner_locations(seller_id, tax_only: true)
  end

  def inventory?
    line_items.all?(&:inventory?)
  end

  def artsy_collects_sales_tax?
    @artsy_collects_sales_tax ||= partner[:artsy_collects_sales_tax]
  end

  def current_commission_rate
    @current_commission_rate ||=
      begin
        current_rate = partner[:effective_commission_rate]
        if current_rate.blank?
          raise Errors::ValidationError, :missing_commission_rate
        end

        current_rate
      end
  end
end
