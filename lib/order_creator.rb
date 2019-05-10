class OrderCreator
  attr_reader :errors
  def initialize(
    buyer_id:,
    buyer_type:,
    mode:,
    quantity: 1,
    artwork_id:,
    edition_set_id: nil,
    user_agent:,
    user_ip:
  )
    @errors = []
    @valid = nil
    @buyer_id = buyer_id
    @buyer_type = buyer_type
    @mode = mode
    @quantity = quantity
    @artwork_id = artwork_id
    @edition_set_id = edition_set_id
    @user_agent = user_agent
    @user_ip = user_ip
  end

  def valid?
    @valid ||=
      valid_artwork? && valid_edition_set? && valid_action? && valid_price?
  end

  def find_or_create!(&post_create_block)
    existing_order || create!(&post_create_block)
  end

  def create!
    raise Errors::ValidationError, @errors.first unless valid?

    @order ||=
      begin
        created_order = create_order
        yield(created_order) if block_given?
        created_order
      end
  rescue ActiveRecord::RecordInvalid => e
    raise Errors::ValidationError.new(:invalid_order, message: e.message)
  end

  private

  def valid_artwork?
    artwork_error =
      if artwork.nil?
        :unknown_artwork
      elsif !artwork[:published]
        :unpublished_artwork
      end
    @errors << artwork_error if artwork_error
    artwork_error.nil?
  end

  def valid_edition_set?
    artwork_error =
      if edition_set_id.present? &&
         !artwork[:edition_sets]&.any? { |e| e[:id] == edition_set_id }
        :unknown_edition_set
      elsif edition_set_id.nil? && artwork[:edition_sets].present? &&
            artwork[:edition_sets].count > 1
        :missing_edition_set_id
      end
    @errors << artwork_error if artwork_error
    artwork_error.nil?
  end

  def valid_action?
    action_error =
      if @mode == Order::BUY && !artwork[:acquireable]
        :not_acquireable
      elsif @mode == Order::OFFER && !artwork[:offerable]
        :not_offerable
      end
    @errors << action_error if action_error.present?
    action_error.nil?
  end

  def valid_price?
    item = edition_set.presence || artwork
    unless item.present? && item[:price_listed]&.positive?
      price_error = :missing_price
    end
    if item.present? && item[:price_currency].blank?
      price_error ||= :missing_currency
    end
    @errors << price_error if price_error.present?
    price_error.nil?
  end

  def existing_order
    @existing_order ||=
      Order.joins(:line_items).find_by(
        mode: @mode,
        buyer_id: @buyer_id,
        buyer_type: @buyer_type,
        state: [Order::PENDING, Order::SUBMITTED],
        line_items: {
          artwork_id: @artwork_id,
          edition_set_id: edition_set_id,
          quantity: @quantity
        }
      )
  end

  def edition_set_id
    @edition_set_id ||=
      begin
        # If artwork has EditionSet but it was not passed in the request
        # if there are more than one EditionSet we'll raise error
        # if there is one we are going to assume thats the one buyer meant to buy
        # TODO: ☝ is a temporary logic till Eigen starts supporting editionset artworks
        # https://artsyproduct.atlassian.net/browse/PURCHASE-505
        if artwork[:edition_sets].present? && artwork[:edition_sets].count == 1
          artwork[:edition_sets].first[:id]
        end
      end
  end

  def artwork
    @artwork ||= Gravity.get_artwork(@artwork_id)
  end

  def edition_set
    if artwork.present? && edition_set_id.present?
      @edition_set ||=
        artwork[:edition_sets].find { |e| e[:id] == edition_set_id }
    end
  end

  def artwork_price
    item = edition_set.presence || artwork
    # TODO: 🚨 update gravity to expose amount in cents and remove this duplicate logic
    # https://github.com/artsy/gravity/blob/65e398e3648d61175e7a8f4403a2d379b5aa2107/app/models/util/for_sale.rb#L221
    UnitConverter.convert_dollars_to_cents(item[:price_listed])
  end

  def create_order
    Order.transaction do
      order =
        Order.create!(
          mode: @mode,
          buyer_id: @buyer_id,
          buyer_type: @buyer_type,
          seller_id: artwork[:partner][:_id],
          seller_type: artwork[:partner][:type].downcase,
          currency_code: artwork[:price_currency],
          state: Order::PENDING,
          state_updated_at: Time.now.utc,
          state_expires_at: Order::STATE_EXPIRATIONS[Order::PENDING].from_now,
          original_user_agent: @user_agent,
          original_user_ip: @user_ip,
          payment_method: Order::CREDIT_CARD # Default to credit card payment method
        )

      line_item =
        order.line_items.create!(
          artwork_id: @artwork_id,
          artwork_version_id: artwork[:current_version_id],
          edition_set_id: edition_set_id,
          list_price_cents: artwork_price,
          quantity: @quantity
        )
      if @mode == Order::BUY
        order.update!(items_total_cents: line_item.total_list_price_cents)
      end
      order
    end
  end
end
