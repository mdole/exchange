require 'rails_helper'

RSpec.describe PostTransactionNotificationJob, type: :job do
  let(:order) { Fabricate(:order) }
  let(:transaction) do
    Fabricate(
      :transaction,
      failure_code: 'stolen_card',
      failure_message: 'nvm! left the card at home',
      order: order
    )
  end
  it 'finds the transaction and posts the event' do
    expect(Artsy::EventService).to receive(:post_event).with(
      topic: 'commerce', event: instance_of(TransactionEvent)
    )
    PostTransactionNotificationJob.new.perform(
      transaction.id,
      TransactionEvent::CREATED,
      order.buyer_id
    )
  end
end
