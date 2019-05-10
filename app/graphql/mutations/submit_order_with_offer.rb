class Mutations::SubmitOrderWithOffer < Mutations::BaseMutation
  null true

  argument :offer_id, ID, required: true

  field :order_or_error,
        Mutations::OrderOrFailureUnionType,
        'A union of success/failure',
        null: false

  def resolve(offer_id:)
    offer = Offer.find(offer_id)
    authorize_offer_owner_request!(offer)

    OfferService.submit_order_with_offer(offer, current_user_id)

    { order_or_error: { order: offer.order } }
  rescue Errors::ApplicationError => e
    {
      order_or_error: { error: Types::ApplicationErrorType.from_application(e) }
    }
  end
end
