module Gravity
  def self.fetch_partner(partner_id)
    Adapters::GravityV1.get("/partner/#{partner_id}/all")
  rescue Adapters::GravityNotFoundError
    raise Errors::ValidationError.new(:unknown_partner, partner_id: partner_id)
  rescue Adapters::GravityError, StandardError => e
    raise Errors::InternalError.new(:gravity, message: e.message)
  end

  def self.get_merchant_account(partner_id)
    merchant_account =
      Adapters::GravityV1.get(
        '/merchant_accounts',
        params: { partner_id: partner_id }
      )
        .first
    if merchant_account.nil?
      raise Errors::ValidationError.new(
              :missing_merchant_account,
              partner_id: partner_id
            )
    end

    merchant_account
  rescue Adapters::GravityNotFoundError
    raise Errors::ValidationError.new(
            :missing_merchant_account,
            partner_id: partner_id
          )
  rescue Adapters::GravityError, StandardError => e
    raise Errors::InternalError.new(:gravity, message: e.message)
  end

  def self.get_credit_card(credit_card_id)
    Adapters::GravityV1.get("/credit_card/#{credit_card_id}")
  rescue Adapters::GravityNotFoundError
    raise Errors::ValidationError.new(
            :credit_card_not_found,
            credit_card_id: credit_card_id
          )
  rescue Adapters::GravityError, StandardError => e
    raise Errors::InternalError.new(:gravity, message: e.message)
  end

  def self.get_artwork(artwork_id)
    Adapters::GravityV1.get("/artwork/#{artwork_id}")
  rescue Adapters::GravityError, StandardError => e
    Rails.logger.warn(
      "Could not fetch artwork #{artwork_id} from gravity: #{e.message}"
    )
    nil
  end

  def self.fetch_partner_locations(partner_id, tax_only: false)
    url = "/partner/#{partner_id}/locations"
    params = { private: true }
    if tax_only
      params = params.merge(address_type: ['Business', 'Sales tax nexus'])
    end
    locations = Adapters::GravityV1.get(url, params: params)
    if locations.blank?
      raise Errors::ValidationError.new(
              :missing_partner_location,
              partner_id: partner_id
            )
    end

    locations.map { |loc| Address.new(loc) }
  rescue Adapters::GravityNotFoundError
    raise Errors::ValidationError.new(:unknown_partner, partner_id: partner_id)
  rescue Adapters::GravityError
    raise Errors::InternalError.new(:gravity, message: e.message)
  end

  def self.deduct_inventory(line_item)
    if line_item.edition_set_id
      Adapters::GravityV1.put(
        "/artwork/#{line_item.artwork_id}/edition_set/#{
          line_item.edition_set_id
        }/inventory",
        params: { deduct: line_item.quantity }
      )
    else
      Adapters::GravityV1.put(
        "/artwork/#{line_item.artwork_id}/inventory",
        params: { deduct: line_item.quantity }
      )
    end
  rescue Adapters::GravityNotFoundError
    raise Errors::ValidationError.new(
            :unknown_artwork,
            line_item_id: line_item.id
          )
  rescue Adapters::GravityError
    raise Errors::ProcessingError.new(
            :insufficient_inventory,
            line_item_id: line_item.id
          )
  end

  def self.undeduct_inventory(line_item)
    if line_item.edition_set_id
      Adapters::GravityV1.put(
        "/artwork/#{line_item.artwork_id}/edition_set/#{
          line_item.edition_set_id
        }/inventory",
        params: { undeduct: line_item.quantity }
      )
    else
      Adapters::GravityV1.put(
        "/artwork/#{line_item.artwork_id}/inventory",
        params: { undeduct: line_item.quantity }
      )
    end
  rescue Adapters::GravityNotFoundError
    raise Errors::ValidationError.new(
            :unknown_artwork,
            line_item_id: line_item.id
          )
  rescue Adapters::GravityError
    raise Errors::ProcessingError.new(
            :undeduct_inventory_failure,
            line_item_id: line_item.id
          )
  end

  def self.get_user(user_id)
    Adapters::GravityV1.get("/user/#{user_id}")
  rescue Adapters::GravityError, StandardError => e
    Rails.logger.warn(
      "Could not fetch user #{user_id} from gravity: #{e.message}"
    )
    nil
  end
end
