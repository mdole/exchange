require 'rails_helper'
require 'support/gravity_helper'

describe Tax::CollectionService, type: :services do
  let(:taxjar_client) { double }
  let(:shipping_region) { 'NY' }
  let(:postal_code) { '10013' }
  let(:shipping) do
    {
      shipping_country: 'US',
      shipping_postal_code: postal_code,
      shipping_region: shipping_region,
      shipping_city: 'New York',
      shipping_address_line1: '123 Fake St'
    }
  end
  let(:fulfillment_type) { Order::SHIP }
  let(:order) do
    Fabricate(:order, id: 1, fulfillment_type: fulfillment_type, **shipping)
  end
  let(:should_remit_sales_tax) { true }
  let!(:line_item) do
    Fabricate(
      :line_item,
      id: 1,
      order: order,
      list_price_cents: 2000_00,
      artwork_id: 'gravity_artwork_1',
      sales_tax_cents: 100,
      should_remit_sales_tax: should_remit_sales_tax
    )
  end
  let(:shipping_total_cents) { 2_222 }
  let(:transaction_id) { "#{line_item.order.id}__#{line_item.id}" }
  let(:shipping_address) do
    Address.new(
      country: 'US',
      postal_code: postal_code,
      region: shipping_region,
      city: 'New York',
      address_line1: '123 Fake St'
    )
  end
  let!(:seller_locations) do
    [
      {
        country: 'US',
        state: 'NY',
        city: 'New York',
        address: '456 Fake St',
        postal_code: '10013'
      },
      {
        country: 'US',
        state: 'MA',
        city: 'Cambridge',
        address: '789 Fake St',
        postal_code: '02139'
      }
    ]
  end
  let!(:seller_addresses) { seller_locations.map { |ad| Address.new(ad) } }
  let(:artwork_location) { Address.new(gravity_v1_artwork[:location]) }
  let(:base_tax_params) do
    {
      amount:
        UnitConverter.convert_cents_to_dollars(line_item.list_price_cents),
      nexus_addresses:
        seller_addresses.map do |ad|
          {
            country: ad.country,
            zip: ad.postal_code,
            state: ad.region,
            city: ad.city,
            street: ad.street_line1
          }
        end,
      to_country: shipping_address.country,
      to_zip: shipping_address.postal_code,
      to_state: shipping_address.region,
      to_city: shipping_address.city,
      to_street: shipping_address.street_line1,
      shipping: 0
    }
  end
  let(:tax_response) { double(amount_to_collect: 3.00) }
  let(:tax_response_with_breakdown) do
    double(
      amount_to_collect: 3.00, breakdown: double(state_tax_collectable: 2.00)
    )
  end
  let(:untaxable_address) { Address.new(country: 'IR') }

  before do
    allow(Taxjar::Client).to receive(:new).with(
      api_key: Rails.application.config_for(:taxjar)['taxjar_api_key'],
      api_url: nil
    )
      .and_return(taxjar_client)
    @service =
      Tax::CollectionService.new(line_item, artwork_location, seller_addresses)
  end

  describe '#initialize' do
    context 'with a destination address in a remitting state' do
      it 'sets seller_nexus_addresses to only be taxable seller addresses' do
        service =
          Tax::CollectionService.new(
            line_item,
            artwork_location,
            seller_addresses + [untaxable_address]
          )
        expect(
          service.instance_variable_get(:@seller_nexus_addresses)
        ).to eq seller_addresses
      end
    end
  end

  describe '#destination_address' do
    context 'with a fulfillment_type of SHIP' do
      context 'with a valid address' do
        it 'returns the shipping address' do
          expect(@service.send(:destination_address)).to eq shipping_address
        end
      end
      context 'with an invalid address' do
        context 'with missing region' do
          let(:shipping_region) { nil }
          it 'raises a missing_region error' do
            service =
              Tax::CollectionService.new(
                line_item,
                artwork_location,
                seller_addresses
              )
            expect {
              service.send(:destination_address)
            }.to raise_error do |error|
              expect(error).to be_a Errors::ValidationError
              expect(error.type).to eq :validation
              expect(error.code).to eq :missing_region
            end
          end
        end
        context 'with missing postal code' do
          let(:postal_code) { nil }
          it 'raises a missing_postal_code error' do
            service =
              Tax::CollectionService.new(
                line_item,
                artwork_location,
                seller_addresses
              )
            expect {
              service.send(:destination_address)
            }.to raise_error do |error|
              expect(error).to be_a Errors::ValidationError
              expect(error.type).to eq :validation
              expect(error.code).to eq :missing_postal_code
            end
          end
        end
      end
    end
    context 'with a fulfillment_type of PICKUP' do
      let(:fulfillment_type) { Order::PICKUP }
      context 'with a valid address' do
        it 'returns the origin address' do
          expect(@service.send(:destination_address)).to eq artwork_location
        end
      end
      context 'with an invalid address' do
        context 'with missing region' do
          it 'raises an invalid_artwork_address error' do
            invalid_artwork_location =
              Address.new(country: 'US', postal_code: '10013')
            service =
              Tax::CollectionService.new(
                line_item,
                invalid_artwork_location,
                seller_addresses
              )
            expect {
              service.send(:destination_address)
            }.to raise_error do |error|
              expect(error).to be_a Errors::ValidationError
              expect(error.type).to eq :validation
              expect(error.code).to eq :invalid_artwork_address
            end
          end
        end
        context 'with missing postal code' do
          it 'raises an invalid_artwork_address error' do
            invalid_artwork_location = Address.new(country: 'US', region: 'NY')
            service =
              Tax::CollectionService.new(
                line_item,
                invalid_artwork_location,
                seller_addresses
              )
            expect {
              service.send(:destination_address)
            }.to raise_error do |error|
              expect(error).to be_a Errors::ValidationError
              expect(error.type).to eq :validation
              expect(error.code).to eq :invalid_artwork_address
            end
          end
        end
      end
    end
  end

  describe '#record_tax_collected' do
    context 'when Artsy needs to remit taxes and line item has sales tax' do
      it 'calls post_transaction and saves the result to @transaction' do
        expect(@service).to receive(:post_transaction).and_return(
          double(transaction_id: '123')
        )
        @service.record_tax_collected
        expect(@service.transaction).to_not be_nil
      end
      context 'with an error from TaxJar' do
        before do
          order.submit!
          order.approve!
        end
        it 'raises a ProcessingError with a code of tax_recording_failure' do
          expect(taxjar_client).to receive(:create_order).and_raise(
            Taxjar::Error
          )
          expect { @service.record_tax_collected }.to raise_error do |error|
            expect(error).to be_a Errors::ProcessingError
            expect(error.type).to eq :processing
            expect(error.code).to eq :tax_recording_failure
          end
        end
      end
    end
    context 'when Artsy does not need to remit taxes' do
      let(:should_remit_sales_tax) { false }
      it 'does nothing' do
        expect(@service).to_not receive(:post_transaction)
        @service.record_tax_collected
      end
    end
    context 'when line item does not have sales tax' do
      it 'does nothing' do
        line_item.sales_tax_cents = 0
        service =
          Tax::CollectionService.new(
            line_item,
            artwork_location,
            seller_addresses
          )
        allow(service).to receive(:post_transaction)
        service.record_tax_collected
        expect(service).to_not have_received(:post_transaction)
      end
    end
  end

  describe '#post_transaction' do
    let(:params) do
      base_tax_params.merge(
        transaction_id: transaction_id,
        transaction_date: line_item.order.last_approved_at.iso8601,
        sales_tax:
          UnitConverter.convert_cents_to_dollars(line_item.sales_tax_cents)
      )
    end
    before do
      # We need to trigger the state actions to generate the state history
      # necessary for `last_updated_at`
      order.submit!
      order.approve!
    end
    it 'calls the Taxjar API with the correct parameters' do
      expect(taxjar_client).to receive(:create_order).with(params)
      @service.send(:post_transaction)
    end
  end

  describe '#refund_transaction' do
    context 'with an existing transaction in Taxjar' do
      it 'refunds the transaction' do
        expect(taxjar_client).to receive(:show_order).with(transaction_id)
          .and_return(double)
        expect(@service).to receive(:post_refund)
        @service.refund_transaction(Time.new(2_018, 1, 1))
      end
    end
    context 'without an existing transaction in Taxjar' do
      it 'does nothing' do
        expect(taxjar_client).to receive(:show_order).with(transaction_id)
          .and_return(nil)
        expect(@service).to_not receive(:post_refund)
        @service.refund_transaction(Time.new(2_018, 1, 1))
      end
    end
    context 'with an error from TaxJar' do
      it 'raises a ProcessingError with a code of tax_refund_failure' do
        expect(taxjar_client).to receive(:show_order).and_raise(Taxjar::Error)
        expect {
          @service.refund_transaction(Time.new(2_018, 1, 1))
        }.to raise_error do |error|
          expect(error).to be_a Errors::ProcessingError
          expect(error.type).to eq :processing
          expect(error.code).to eq :tax_refund_failure
        end
      end
    end
  end

  describe '#get_transaction' do
    it "returns nil if TaxJar can't find the associated record" do
      expect(taxjar_client).to receive(:show_order).and_raise(
        Taxjar::Error::NotFound
      )
      expect(@service.send(:get_transaction, 'tx_id')).to be_nil
    end
  end

  describe '#post_refund' do
    let(:transaction_date) { Time.new(2_018, 1, 1) }
    let(:params) do
      base_tax_params.merge(
        transaction_id: "refund_#{transaction_id}",
        transaction_date: transaction_date.iso8601,
        transaction_reference_id: transaction_id,
        sales_tax:
          UnitConverter.convert_cents_to_dollars(line_item.sales_tax_cents)
      )
    end
    it 'calls the TaxJar API with the correct parameters' do
      expect(taxjar_client).to receive(:create_refund).with(params)
      @service.send(:post_refund, transaction_date)
    end
  end

  describe '#construct_tax_params' do
    it 'returns the parameters shared by all API calls to TaxJar' do
      expect(@service.send(:construct_tax_params)).to eq base_tax_params
    end
    it 'merges in additional data' do
      additional_data = { foo: 'bar' }
      expect(
        @service.send(:construct_tax_params, additional_data)
      ).to eq base_tax_params.merge(additional_data)
    end
  end

  describe '#address_taxable?' do
    context 'with a US-based address' do
      it 'returns true' do
        expect(
          @service.send(
            :address_taxable?,
            Address.new(country: 'US', region: 'FL', postal_code: '12345')
          )
        ).to eq true
      end
    end
    context 'with a non-US-based address' do
      it 'returns false' do
        expect(@service.send(:address_taxable?, untaxable_address)).to eq false
      end
    end
  end

  describe '#process_nexus_addresses' do
    context 'with no addresses' do
      it 'raises an error' do
        expect {
          @service.send(:process_nexus_addresses!, [])
        }.to raise_error do |error|
          expect(error).to be_a Errors::ValidationError
          expect(error.type).to eq :validation
          expect(error.code).to eq :no_taxable_addresses
        end
      end
    end
    context 'with no valid taxable addresses' do
      it 'raises an error' do
        expect {
          @service.send(:process_nexus_addresses!, [untaxable_address])
        }.to raise_error do |error|
          expect(error).to be_a Errors::ValidationError
          expect(error.type).to eq :validation
          expect(error.code).to eq :no_taxable_addresses
        end
      end
    end
    context 'with taxable addresses' do
      it 'filters out non-taxable addresses' do
        addresses = seller_addresses + [untaxable_address]
        expect(
          @service.send(:process_nexus_addresses!, addresses)
        ).to eq seller_addresses
      end
      it 'validates taxable addresses' do
        seller_addresses.each do |ad|
          expect(@service).to receive(:validate_nexus_address!).with(ad)
        end
        @service.send(:process_nexus_addresses!, seller_addresses)
      end
    end
  end
  context '#validate_nexus_address!' do
    context 'with an address with a missing region' do
      it 'raises an error' do
        invalid_address = Address.new(country: 'US')
        expect {
          @service.send(:validate_nexus_address!, invalid_address)
        }.to raise_error do |error|
          expect(error).to be_a Errors::ValidationError
          expect(error.type).to eq :validation
          expect(error.code).to eq :invalid_seller_address
        end
      end
    end
  end
end
