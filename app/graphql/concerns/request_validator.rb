module RequestValidator
  def authorize_seller_request!(order)
    raise Errors::ValidationError, :not_found unless authorized_seller?(order)
  end

  def authorize_buyer_request!(item)
    raise Errors::ValidationError, :not_found unless authorized_buyer?(item)
  end

  def authorize_offer_owner_request!(offer)
    unless context[:current_user]['id'] == offer.from_id &&
           offer.from_type == Order::USER
      raise Errors::ValidationError, :not_found
    end
  end

  def authorized_seller?(item)
    order =
      case item
      when Order
        item
      when Offer
        item.order
      end
    current_user_is_on_seller =
      context[:current_user]['partner_ids'].include?(order.seller_id)
    order.seller_type != Order::USER && current_user_is_on_seller
  end

  def authorized_buyer?(item)
    case item
    when Order
      context[:current_user]['id'] == item.buyer_id
    when Offer
      context[:current_user]['id'] == item.order.buyer_id
    else
      raise Errors::ValidationError, :not_found
    end
  end
end
