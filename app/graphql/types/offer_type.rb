class Types::OfferType < Types::BaseObject
  description 'An Offer'
  graphql_name 'Offer'

  field :id, ID, null: false
  field :from, Types::OrderPartyUnionType, null: false
  field :amount_cents, Integer, null: false
  field :tax_total_cents, Integer, null: true
  field :shipping_total_cents, Integer, null: true
  field :creator_id, String, null: false
  field :created_at, Types::DateTimeType, null: false
  field :submitted_at, Types::DateTimeType, null: true
  field :order, Types::OrderInterface, null: false
  field :responds_to, Types::OfferType, null: true
  field :from_participant, Types::OrderParticipantEnum, null: true
  field :buyer_total_cents, Integer, null: true
  field :note, String, null: true

  def from
    OpenStruct.new(id: object.from_id, type: object.from_type)
  end
end
