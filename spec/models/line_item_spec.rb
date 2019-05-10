require 'rails_helper'

describe LineItem, type: :model do
  let(:mode) { Order::BUY }
  let(:order) { Fabricate(:order, mode: mode) }

  it_behaves_like 'a papertrail versioned model', :line_item

  describe 'validation' do
    context 'Buy Order' do
      it 'can create many line items' do
        expect {
          order.line_items.create!(quantity: 2)
          order.line_items.create!(quantity: 3)
        }.to change(order.line_items, :count).by(2)
      end
    end

    context 'Offer Order' do
      let(:mode) { Order::OFFER }
      it 'creates line item' do
        expect { order.line_items.create!(quantity: 2) }.to change(
          order.line_items,
          :count
        )
          .by(1)
      end
      it 'raises error when creating second line item' do
        order.line_items.create!(quantity: 2)
        expect { order.line_items.create!(quantity: 4) }.to raise_error(
          ActiveRecord::RecordInvalid,
          /Order offer order can only have one line item/
        )
      end
    end
  end

  describe '#total_list_price_cents' do
    it 'returns proper list price' do
      line_item = Fabricate(:line_item, list_price_cents: 200, quantity: 3)
      expect(line_item.total_list_price_cents).to eq 600
    end
  end
end
