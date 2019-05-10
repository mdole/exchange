require 'rails_helper'

describe Api::GraphqlController, type: :request do
  describe 'line_items query' do
    include_context 'GraphQL Client'
    let(:seller_id) { jwt_partner_ids.first }
    let(:user_id) { jwt_user_id }
    let(:jwt_roles) { 'trusted' }

    let(:artwork_id) { 'a-1' }
    let(:edition_set_id) { 'e-1' }
    let(:order1) do
      Fabricate(
        :order,
        seller_id: seller_id, buyer_id: user_id, state: Order::PENDING
      )
    end
    let!(:line_item1) do
      Fabricate(
        :line_item,
        order: order1,
        artwork_id: artwork_id,
        edition_set_id: edition_set_id,
        quantity: 2
      )
    end
    let(:order2) do
      Fabricate(
        :order,
        seller_id: seller_id, buyer_id: user_id, state: Order::SUBMITTED
      )
    end
    let!(:line_item2) do
      Fabricate(
        :line_item,
        order: order2,
        artwork_id: artwork_id,
        edition_set_id: edition_set_id,
        quantity: 2
      )
    end
    let(:order3) do
      Fabricate(
        :order,
        seller_id: seller_id, buyer_id: user_id, state: Order::FULFILLED
      )
    end
    let!(:line_item3) do
      Fabricate(
        :line_item,
        order: order3,
        artwork_id: artwork_id,
        edition_set_id: edition_set_id,
        quantity: 2
      )
    end
    let(:order4) do
      Fabricate(
        :order,
        seller_id: seller_id, buyer_id: user_id, state: Order::FULFILLED
      )
    end
    let!(:line_item4) do
      Fabricate(
        :line_item,
        order: order3, artwork_id: 'foo', edition_set_id: 'bar', quantity: 2
      )
    end

    let(:query) do
      <<-GRAPHQL
        query($artworkId: String, $editionSetId: String, $orderStates: [OrderStateEnum!]) {
          lineItems(artworkId: $artworkId, editionSetId: $editionSetId, orderStates: $orderStates) {
            edges {
              node {
                id
                listPriceCents
                artworkId
                editionSetId
                order {
                  id
                }
              }
            }
          }
        }
      GRAPHQL
    end

    it 'returns error when missing both artworkId and editionSetId' do
      expect {
        client.execute(query, order_states: %w[CANCELED])
      }.to raise_error do |error|
        expect(error).to be_a(Graphlient::Errors::ServerError)
        expect(error.message).to eq 'the server responded with status 400'
        expect(error.status_code).to eq 400
        expect(
          error.response['errors'].first['extensions']['code']
        ).to eq 'missing_params'
        expect(
          error.response['errors'].first['extensions']['type']
        ).to eq 'validation'
      end
    end

    context 'query with artworkId' do
      it 'returns line items' do
        result = client.execute(query, artworkId: artwork_id)
        expect(result.data.line_items.edges.count).to eq 3
        expect(
          result.data.line_items.edges.first.node.artwork_id
        ).to eq artwork_id
        expect(result.data.line_items.edges.first.node.order.id).to eq order1.id
      end
    end

    context 'query with editionSetId' do
      it 'returns line items' do
        result = client.execute(query, editionSetId: edition_set_id)
        expect(result.data.line_items.edges.count).to eq 3
        expect(
          result.data.line_items.edges.first.node.edition_set_id
        ).to eq edition_set_id
        expect(result.data.line_items.edges.first.node.order.id).to eq order1.id
      end
    end

    context 'query with artworkId and orderStates' do
      it 'returns line items' do
        result =
          client.execute(
            query,
            artworkId: artwork_id, orderStates: %w[SUBMITTED FULFILLED]
          )
        expect(result.data.line_items.edges.count).to eq 2
        expect(
          result.data.line_items.edges.first.node.artwork_id
        ).to eq artwork_id
        expect(result.data.line_items.edges.first.node.order.id).to eq order2.id
      end
    end

    context 'authentication' do
      context 'untrusted app' do
        let(:jwt_roles) { 'foobar' }
        it 'raises error' do
          expect {
            client.execute(query, artworkId: artwork_id)
          }.to raise_error do |error|
            expect(error).to be_a(Graphlient::Errors::ServerError)
            expect(error.status_code).to eq 400
            expect(error.message).to eq 'the server responded with status 400'
            expect(
              error.response['errors'].first['extensions']['code']
            ).to eq 'not_found'
            expect(
              error.response['errors'].first['extensions']['type']
            ).to eq 'validation'
          end
        end
      end
    end
  end
end
