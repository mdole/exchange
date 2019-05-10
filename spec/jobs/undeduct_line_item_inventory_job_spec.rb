require 'rails_helper'

RSpec.describe UndeductLineItemInventoryJob, type: :job do
  let(:order) { Fabricate(:order) }
  let!(:line_items) do
    [
      Fabricate(
        :line_item,
        order: order, artwork_id: 'a-1', list_price_cents: 123_00
      )
    ]
  end
  let(:artwork_inventory_deduct_request_status) { 200 }
  let(:edition_set_inventory_deduct_request_status) { 200 }
  let(:artwork_inventory_undeduct_request) do
    stub_request(
      :put,
      "#{
        Rails.application.config_for(:gravity)['api_v1_root']
      }/artwork/a-1/inventory"
    )
      .with(body: { undeduct: 1 })
      .to_return(
      status: artwork_inventory_deduct_request_status, body: {}.to_json
    )
  end
  let(:edition_set_inventory_undeduct_request) do
    stub_request(
      :put,
      "#{
        Rails.application.config_for(:gravity)['api_v1_root']
      }/artwork/a-2/edition_set/es-1/inventory"
    )
      .with(body: { undeduct: 2 })
      .to_return(
      status: edition_set_inventory_deduct_request_status, body: {}.to_json
    )
  end
  it 'finds the order and undeducts inventory of each line item' do
    artwork_inventory_undeduct_request
    edition_set_inventory_undeduct_request
    UndeductLineItemInventoryJob.new.perform(line_items.first.id)
  end
end
