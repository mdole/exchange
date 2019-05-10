module Errors
  class ApplicationError < StandardError
    attr_reader :type, :code, :data
    def initialize(type, code, data = nil, post_event = false)
      unless ERROR_TYPES[type].include?(code)
        raise "Invalid type: #{type} or #{
                code
              }. Make sure to add/reuse codes in error_types.rb"
      end

      @type = type
      @code = code
      @data = data
      post_error_event if post_event
      super(type)
    end

    private

    def post_error_event
      event = ApplicationErrorEvent.new(self)
      PostEventJob.perform_later(
        ApplicationErrorEvent::TOPIC,
        event.to_json,
        event.routing_key
      )
    end
  end
end
