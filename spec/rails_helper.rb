# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
# Prevent database truncation if the environment is production
if Rails.env.production?
  abort('The Rails environment is running in production mode!')
end
require 'rspec/rails'
require 'webmock/rspec'
require 'selenium/webdriver'
# Add additional requires below this line. Rails is not loaded until this point!
require 'paper_trail/frameworks/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

Dir['./spec/support/**/*.rb'].each { |f| require f }

ActiveRecord::Migration.maintain_test_schema!

Capybara.register_driver :chrome_headless do |app|
  options = ::Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

RSpec.configure do |config|
  config.filter_rails_from_backtrace!
  config.infer_spec_type_from_file_location!
  config.use_transactional_fixtures = true
  config.before { ActiveJob::Base.queue_adapter = :test }
end

RSpec.configure do |config|
  config.before(:all, type: :system) do
    Capybara.server = :puma, { Silent: true }
  end

  config.before(:each, type: :system) { driven_by :rack_test }

  config.before(:each, type: :system, js: true) { driven_by :chrome_headless }
end
