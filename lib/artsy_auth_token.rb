class ArtsyAuthToken
  ADMIN_ROLE = 'sales_admin'.freeze
  def initialize(jwt)
    @jwt = jwt
    @decoded_token = decode_token
  end

  def admin?
    return false unless @decoded_token

    @decoded_token['roles'].include? ADMIN_ROLE
  end

  def current_user
    @decoded_token.merge(id: @decoded_token[:sub])
  end

  private

  def decode_token
    JWT.decode(
      @jwt,
      Rails.application.config_for(:jwt)['hmac_secret'],
      true,
      algorithm: 'HS256'
    )[
      0
    ]
      .with_indifferent_access
  end
end
