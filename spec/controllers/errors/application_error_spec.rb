require 'rails_helper'

describe Errors::ApplicationError do
  describe 'post_error_event' do
    it 'posts application_error_event when asked for' do
      Errors::ApplicationError.new(
        :validation,
        :missing_region,
        { what_was_invalid: 'everything!' },
        true
      )
      expect(PostEventJob).to have_been_enqueued.with(
        'commerce',
        kind_of(String),
        'error.validation.missing_region'
      )
    end
    it 'wont post application_error_event by default' do
      Errors::ApplicationError.new(
        :validation,
        :missing_region,
        what_was_invalid: 'everything!'
      )
      expect(PostEventJob).not_to have_been_enqueued
    end
    it 'wont post application_error_event when not requested' do
      Errors::ApplicationError.new(
        :validation,
        :missing_region,
        { what_was_invalid: 'everything!' },
        false
      )
      expect(PostEventJob).not_to have_been_enqueued
    end
  end
end
