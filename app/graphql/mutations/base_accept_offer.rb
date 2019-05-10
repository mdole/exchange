class Mutations::BaseAcceptOffer < Mutations::BaseMutation
  null true

  argument :offer_id, ID, required: true

  field :order_or_error,
        Mutations::OrderOrFailureUnionType,
        'A union of success/failure',
        null: false

  def resolve(offer_id:)
    offer = Offer.find(offer_id)

    authorize!(offer)
    unless waiting_for_accept?(offer)
      raise Errors::ValidationError, :cannot_accept_offer
    end

    OfferService.accept_offer(offer, current_user_id)
    { order_or_error: { order: offer.order } }
  rescue Errors::ApplicationError => e
    {
      order_or_error: { error: Types::ApplicationErrorType.from_application(e) }
    }
  end

  def authorize!(_offer)
    raise NotImplementedError
  end

  def waiting_for_accept?(_offer)
    raise NotImplementedError
  end
end
