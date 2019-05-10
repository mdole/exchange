module LineItemHelper
  def artwork
    @artwork ||=
      begin
        artwork = Gravity.get_artwork(artwork_id)
        validate_artwork!(artwork)
        artwork
      end
  end

  def inventory?
    inventory =
      if edition_set_id.present?
        edition_set =
          artwork[:edition_sets].detect { |a| a[:id] == edition_set_id }
        raise Errors::ValidationError, :unknown_edition_set unless edition_set

        edition_set[:inventory]
      else
        artwork[:inventory]
      end
    inventory[:count].positive? || inventory[:unlimited]
  end

  def latest_artwork_version?
    artwork[:current_version_id] == artwork_version_id
  end

  def artwork_location
    if artwork[:location].blank?
      raise Errors::ValidationError, :missing_artwork_location
    end

    @artwork_location ||= Address.new(artwork[:location])
  end

  def current_commission_fee_cents
    total_list_price_cents * order.current_commission_rate
  end

  private

  def validate_artwork!(artwork)
    raise Errors::ValidationError, :unknown_artwork unless artwork
    if artwork[:location].blank?
      raise Errors::ValidationError, :missing_artwork_location
    end
  end
end
