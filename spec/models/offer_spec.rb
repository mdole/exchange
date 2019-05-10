require 'rails_helper'

RSpec.describe Offer, type: :model do
  it_behaves_like 'a papertrail versioned model', :offer

  describe 'last_offer?' do
    it "returns true if the offer is the order's last offer" do
      order = Fabricate(:order)
      offer = Fabricate(:offer, order: order)
      order.update!(last_offer: offer)

      expect(offer.last_offer?).to eq(true)
    end

    it "return false if the offer is not the order's last offer" do
      order = Fabricate(:order)
      first_offer = Fabricate(:offer, order: order)
      second_offer = Fabricate(:offer, order: order)

      order.update!(last_offer: second_offer)

      expect(first_offer.last_offer?).to eq(false)
    end
  end

  describe '#scopes' do
    describe 'submitted' do
      let!(:offer1) { Fabricate(:offer, submitted_at: Time.now) }
      let!(:offer2) { Fabricate(:offer, submitted_at: nil) }
      let!(:offer3) { Fabricate(:offer, submitted_at: nil) }
      it 'returns submitted offers' do
        expect(Offer.submitted).to match_array [offer1]
      end
    end
  end

  describe '#from_participant' do
    let(:order) do
      Fabricate(
        :order,
        buyer_id: 'buyer1',
        buyer_type: 'user',
        seller_id: 'seller1',
        seller_type: 'gallery'
      )
    end
    let(:seller_offer) do
      Fabricate(:offer, order: order, from_id: 'seller1', from_type: 'gallery')
    end
    let(:buyer_offer) do
      Fabricate(:offer, order: order, from_id: 'buyer1', from_type: 'user')
    end
    let(:ufo_offer) do
      Fabricate(:offer, order: order, from_id: 'marse', from_type: 'ufo')
    end
    it 'returns buyer for buyer_offer' do
      expect(buyer_offer.from_participant).to eq Order::BUYER
    end
    it 'returns seller for seller_offer' do
      expect(seller_offer.from_participant).to eq Order::SELLER
    end
    it 'raises error for offer that is not from a buyer or seller' do
      expect { ufo_offer.from_participant }.to raise_error do |error|
        expect(error.type).to eq :validation
        expect(error.code).to eq :unknown_participant_type
      end
    end
  end

  describe '#to_participant' do
    let(:order) do
      Fabricate(
        :order,
        buyer_id: 'buyer1',
        buyer_type: 'user',
        seller_id: 'seller1',
        seller_type: 'gallery'
      )
    end
    let(:seller_offer) do
      Fabricate(:offer, order: order, from_id: 'seller1', from_type: 'gallery')
    end
    let(:buyer_offer) do
      Fabricate(:offer, order: order, from_id: 'buyer1', from_type: 'user')
    end
    let(:ufo_offer) do
      Fabricate(:offer, order: order, from_id: 'marse', from_type: 'ufo')
    end
    it 'returns seller for buyer_offer' do
      expect(buyer_offer.to_participant).to eq Order::SELLER
    end
    it 'returns buyer for seller_offer' do
      expect(seller_offer.to_participant).to eq Order::BUYER
    end
    it 'raises error for offer that is not from a buyer or seller' do
      expect { ufo_offer.from_participant }.to raise_error do |error|
        expect(error.type).to eq :validation
        expect(error.code).to eq :unknown_participant_type
      end
    end
  end
end
