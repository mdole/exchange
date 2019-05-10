class Mutations::FixFailedPayment < Mutations::BaseMutation
  null true

  argument :offer_id, ID, required: true
  argument :credit_card_id, String, required: true

  field :order_or_error,
        Mutations::OrderOrFailureUnionType,
        'A union of success/failure',
        null: false

  def resolve(offer_id:, credit_card_id:)
    offer = Offer.find(offer_id)
    order = offer.order
    authorize_buyer_request!(order)

    unless order.state == Order::SUBMITTED && order.last_transaction_failed? &&
           offer.id == order.last_offer.id
      raise Errors::ValidationError.new(:invalid_state, state: order.state)
    end

    order = OrderService.set_payment!(order, credit_card_id)

    # Note that the buyer might be 'accepting' their own offer here.
    # If they are, we know the seller attepted to accept it before
    # because order.last_transaction_failed? is true.
    OfferService.accept_offer(offer, current_user_id)

    { order_or_error: { order: order.reload } }
  rescue Errors::ApplicationError => e
    {
      order_or_error: { error: Types::ApplicationErrorType.from_application(e) }
    }
  end
end
