class RecordSalesTaxJob < ApplicationJob
  queue_as :default

  def perform(line_item_id)
    line_item = LineItem.find(line_item_id)
    return unless line_item.should_remit_sales_tax?

    artwork = Gravity.get_artwork(line_item.artwork_id)
    artwork_address = Address.new(artwork[:location])
    seller_addresses =
      Gravity.fetch_partner_locations(line_item.order.seller_id, tax_only: true)
    service =
      Tax::CollectionService.new(line_item, artwork_address, seller_addresses)
    service.record_tax_collected
    if service.transaction.present?
      line_item.update!(
        sales_tax_transaction_id: service.transaction.transaction_id
      )
    end
  end
end
