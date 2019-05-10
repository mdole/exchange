require 'rails_helper'
require 'support/taxjar_helper'

describe RecordSalesTaxJob, type: :job do
  let(:order) do
    Fabricate(
      :order,
      fulfillment_type: Order::PICKUP,
      shipping_country: 'US',
      shipping_postal_code: '10013',
      shipping_region: 'NY',
      shipping_city: 'New York',
      shipping_address_line1: '401 Broadway',
      shipping_total_cents: 100,
      state: Order::APPROVED
    )
  end
  let(:should_remit_sales_tax) { true }
  let!(:line_item) do
    Fabricate(
      :line_item,
      order: order,
      sales_tax_cents: 100_00,
      should_remit_sales_tax: should_remit_sales_tax
    )
  end
  let(:artwork_location) do
    {
      country: 'US',
      city: 'New York',
      state: 'NY',
      address: '22 Fake St',
      postal_code: 10_013
    }
  end
  let(:seller_addresses) do
    [Address.new(country: 'US', region: 'NY', postal_code: '10012')]
  end
  describe '#perform' do
    before { stub_tax_for_order }
    context 'with an order that has sales tax to remit' do
      it 'posts a transaction to TaxJar and saves the transaction id' do
        expect(Gravity).to receive(:get_artwork).with(line_item.artwork_id)
          .and_return(gravity_v1_artwork(location: artwork_location))
        expect(Gravity).to receive(:fetch_partner_locations).with(
          line_item.order.seller_id,
          tax_only: true
        )
          .and_return(seller_addresses)
        expect(Address).to receive(:new).with(artwork_location).and_return(
          Address.new(artwork_location)
        )
        RecordSalesTaxJob.perform_now(line_item.id)
        expect(line_item.reload.sales_tax_transaction_id).to eq '123'
      end
      context 'with an order that does not have sales tax to remit' do
        let(:should_remit_sales_tax) { false }
        it 'does nothing' do
          expect(Tax::CollectionService).to_not receive(:new)
          RecordSalesTaxJob.perform_now(line_item.id)
          expect(line_item.reload.sales_tax_transaction_id).to be_nil
        end
      end
    end
  end
end
