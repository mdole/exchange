# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
# Prevent database truncation if the environment is production
abort('The Rails environment is running in production mode!') if Rails.env.production?
require 'rspec/rails'
require 'webmock/rspec'
require 'selenium/webdriver'
# Add additional requires below this line. Rails is not loaded until this point!
require 'paper_trail/frameworks/rspec'

WebMock.disable_net_connect!(allow_localhost: true, allow: 'chromedriver.storage.googleapis.com')

Dir['./spec/support/**/*.rb'].sort.each { |f| require f }

ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.filter_rails_from_backtrace!
  config.infer_spec_type_from_file_location!
  config.use_transactional_fixtures = true
  config.before do
    ActiveJob::Base.queue_adapter = :test
  end
end


def prepare_chromedriver(selenium_driver_args)
  if (driver_path = ENV['CHROMEDRIVER_PATH'])
    service = Selenium::WebDriver::Service.new(path: driver_path, port: 9005)
    selenium_driver_args[:service] = service
  else
    require 'webdrivers/chromedriver'
  end
end

Capybara.register_driver :headless_chrome do |app|
  # Internally, WebDriver uses HTTP, and the default Net::HTTP timeout is 60s.
  # Capybara now supports setting the timeout directly and increasing that will
  # help solve the spec timeout issue we've seen on the first spec.
  http_client_read_timout = 120
  caps = Selenium::WebDriver::Remote::Capabilities.chrome(loggingPrefs: { browser: 'ALL' })
  opts = Selenium::WebDriver::Chrome::Options.new(options: { 'w3c' => false })

  opts.add_argument('--headless')
  opts.add_argument('--no-sandbox')
  opts.add_argument('--window-size=1440,900')

  args = {
    browser: :chrome,
    options: opts,
    desired_capabilities: caps,
    timeout: http_client_read_timout
  }

  prepare_chromedriver(args)

  Capybara::Selenium::Driver.new(app, args)
end

Capybara.register_driver :chrome do |app|
  args = { browser: :chrome }
  prepare_chromedriver(args)
  Capybara::Selenium::Driver.new(app, args)
end

Capybara.configure do |config|
  # change this to :chrome to observe tests in a real browser
  config.javascript_driver = ENV.fetch('JAVASCRIPT_DRIVER', :headless_chrome).to_sym
  config.default_max_wait_time = 10
  # Capybara 3 changes the default server to Puma. We should remove this once we also
  # switch the app to Puma.
  config.server = :webrick
  config.default_normalize_ws = true
end

RSpec.configure do |config|
  config.before(:all, type: :system) do
    Capybara.server = :puma, { Silent: true }
  end

  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  config.before(:each, type: :system, js: true) do
    driven_by :headless_chrome
  end
end