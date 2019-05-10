class Mutations::SubmitPendingOffer < Mutations::BaseMutation
  null true

  argument :offer_id, ID, required: true

  field :order_or_error,
        Mutations::OrderOrFailureUnionType,
        'A union of success/failure',
        null: false

  def resolve(offer_id:)
    offer = Offer.find(offer_id)
    authorize_offer_owner_request!(offer)
    unless offer.order.state == Order::SUBMITTED
      raise Errors::ValidationError, :invalid_state
    end

    submitted_offer = OfferService.submit_pending_offer(offer)

    { order_or_error: { order: submitted_offer.order } }
  rescue Errors::ApplicationError => e
    {
      order_or_error: { error: Types::ApplicationErrorType.from_application(e) }
    }
  end
end
