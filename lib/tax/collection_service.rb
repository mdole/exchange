class Tax::CollectionService
  attr_reader :transaction
  def initialize(
    line_item,
    artwork_location,
    nexus_addresses,
    tax_client = Taxjar::Client.new(
      api_key: Rails.application.config_for(:taxjar)['taxjar_api_key'],
      api_url: Rails.application.config_for(:taxjar)['taxjar_api_url'].presence
    )
  )
    @seller_nexus_addresses = process_nexus_addresses!(nexus_addresses)
    @line_item = line_item
    @fulfillment_type = line_item.order.fulfillment_type
    @tax_client = tax_client
    @artwork_location = artwork_location
    @shipping_address = line_item.order.shipping_address
    @shipping_total_cents = line_item.order.shipping_total_cents
    @transaction = nil
    @refund = nil
  end

  def record_tax_collected
    if @line_item.should_remit_sales_tax? &&
       @line_item.sales_tax_cents&.positive?
      @transaction = post_transaction
    end
  rescue Taxjar::Error => e
    raise Errors::ProcessingError.new(
            :tax_recording_failure,
            message: e.message
          )
  end

  def refund_transaction(refund_date)
    @transaction = get_transaction(transaction_id)
    @refund = post_refund(refund_date) if @transaction.present?
  rescue Taxjar::Error => e
    raise Errors::ProcessingError.new(:tax_refund_failure, message: e.message)
  end

  private

  def construct_tax_params(args = {})
    {
      amount:
        UnitConverter.convert_cents_to_dollars(
          @line_item.total_list_price_cents
        ),
      to_country: destination_address.country,
      to_zip: destination_address.postal_code,
      to_state: destination_address.region,
      to_city: destination_address.city,
      to_street: destination_address.street_line1,
      nexus_addresses:
        @seller_nexus_addresses.map do |ad|
          {
            country: ad.country,
            zip: ad.postal_code,
            state: ad.region,
            city: ad.city,
            street: ad.street_line1
          }
        end,
      shipping:
        UnitConverter.convert_cents_to_dollars(@effective_shipping_total_cents)
    }.merge(args)
  end

  def effective_shipping_total_cents
    @effective_shipping_total_cents ||=
      @line_item.should_remit_sales_tax ? @shipping_total_cents : 0
  end

  def destination_address
    @destination_address ||=
      begin
        address =
          if @fulfillment_type == Order::SHIP
            @shipping_address
          else
            @artwork_location
          end
        validate_destination_address!(address)
        address
      rescue Errors::ValidationError => e
        if @fulfillment_type == Order::PICKUP
          raise Errors::ValidationError, :invalid_artwork_address
        end

        raise e
      end
  end

  def address_taxable?(address)
    # For the time being, we're only considering addresses in the United States to be taxable.
    address.united_states?
  end

  def validate_destination_address!(destination_address)
    if destination_address.region.nil?
      raise Errors::ValidationError, :missing_region
    end
    if destination_address.postal_code.nil?
      raise Errors::ValidationError, :missing_postal_code
    end
  end

  def process_nexus_addresses!(seller_nexus_addresses)
    nexus_addresses =
      seller_nexus_addresses.select { |ad| address_taxable?(ad) }
    if nexus_addresses.blank?
      raise Errors::ValidationError, :no_taxable_addresses
    end

    nexus_addresses.each { |ad| validate_nexus_address!(ad) }
    nexus_addresses
  end

  def validate_nexus_address!(nexus_address)
    if nexus_address.region.nil?
      raise Errors::ValidationError, :invalid_seller_address
    end
  end

  def post_transaction
    transaction_date = @line_item.order.last_approved_at.iso8601
    @tax_client.create_order(
      construct_tax_params(
        transaction_id: transaction_id,
        transaction_date: transaction_date,
        sales_tax:
          UnitConverter.convert_cents_to_dollars(@line_item.sales_tax_cents)
      )
    )
  end

  def post_refund(refund_date)
    @tax_client.create_refund(
      construct_tax_params(
        transaction_id: "refund_#{transaction_id}",
        transaction_date: refund_date.iso8601,
        transaction_reference_id: transaction_id,
        sales_tax:
          UnitConverter.convert_cents_to_dollars(@line_item.sales_tax_cents)
      )
    )
  end

  def get_transaction(id)
    @tax_client.show_order(id)
  rescue Taxjar::Error::NotFound
    nil
  end

  def transaction_id
    "#{@line_item.order.id}__#{@line_item.id}"
  end
end
