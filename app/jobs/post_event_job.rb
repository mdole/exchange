class PostEventJob < ApplicationJob
  queue_as :default

  def perform(topic, event_json, routing_key)
    Artsy::EventService.post_data(
      topic: topic, data: event_json, routing_key: routing_key
    )
  end
end
