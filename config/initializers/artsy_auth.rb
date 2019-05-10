ArtsyAuth.configure do |config|
  config.artsy_api_url =
    Rails.application.config_for(:artsy_auth)['artsy_api_url']
  config.callback_url = '/admin'
  config.application_id =
    Rails.application.config_for(:artsy_auth)['application_id']
  config.application_secret =
    Rails.application.config_for(:artsy_auth)['application_secret']
end
