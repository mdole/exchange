class Types::LineItemType < Types::BaseObject
  description 'A Line Item'
  graphql_name 'LineItem'

  field :id, ID, null: false
  field :price_cents,
        Integer,
        null: false, deprecation_reason: 'switch to use listPriceCents'
  field :list_price_cents, Integer, null: false
  field :shipping_total_cents, Integer, null: true
  field :artwork_id, String, null: false
  field :artwork_version_id, String, null: false
  field :edition_set_id, String, null: true
  field :quantity, Integer, null: false
  field :commission_fee_cents, Integer, null: true, seller_only: true
  field :created_at, Types::DateTimeType, null: false
  field :updated_at, Types::DateTimeType, null: false
  field :fulfillments, Types::FulfillmentType.connection_type, null: true
  field :order, Types::OrderInterface, null: false

  def price_cents
    object.list_price_cents
  end
end
