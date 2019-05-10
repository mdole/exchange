require 'rails_helper'

RSpec.describe PostEventJob, type: :job do
  let(:user_id) { 'user_id' }
  let(:order) { Fabricate(:order, buyer_id: user_id, buyer_type: 'user') }
  let!(:line_item) do
    Fabricate(
      :line_item,
      order: order, artwork_id: 'a-1', list_price_cents: 123_00
    )
  end
  let(:event) do
    OrderEvent.new(user: user_id, action: Order::SUBMITTED, model: order)
  end

  it 'post the event with correct topic, event and routing key' do
    expect(Artsy::EventService).to receive(:post_data).with(
      topic: 'commerce', data: event.to_json, routing_key: 'order.submitted'
    )
    PostEventJob.new.perform('commerce', event.to_json, event.routing_key)
  end
end
