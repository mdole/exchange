class UndeductLineItemInventoryJob < ApplicationJob
  queue_as :default
  discard_on(Errors::ValidationError) do |job, _error|
    Rails.warn.info "Line item #{
                      job.line_item.id
                    } has deleted artwork, skipping inventory undeduction"
  end

  attr_accessor :line_item

  def perform(line_item_id)
    @line_item = LineItem.find(line_item_id)
    Gravity.undeduct_inventory(@line_item)
  end
end
