class Mutations::ConfirmPickup < Mutations::BaseMutation
  null true

  argument :id, ID, required: true

  field :order_or_error,
        Mutations::OrderOrFailureUnionType,
        'A union of success/failure',
        null: false

  def resolve(id:)
    order = Order.find(id)
    authorize_seller_request!(order)
    OrderService.confirm_pickup!(order, context[:current_user][:id])

    { order_or_error: { order: order } }
  rescue Errors::ApplicationError => e
    {
      order_or_error: { error: Types::ApplicationErrorType.from_application(e) }
    }
  end
end
