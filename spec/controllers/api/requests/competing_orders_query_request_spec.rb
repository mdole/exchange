require 'rails_helper'

describe Api::GraphqlController, type: :request do
  describe 'competing orders query' do
    include_context 'GraphQL Client'

    let(:query) do
      <<-GRAPHQL
          query($orderId: ID!) {
            competingOrders(orderId: $orderId) {
              totalCount
            }
          }
      GRAPHQL
    end

    context 'without trusted role' do
      let(:jwt_roles) { 'untrusted' }

      it 'raises a graphql error' do
        expect { client.execute(query) }.to raise_error do |error|
          expect(error).to be_a(Graphlient::Errors::GraphQLError)
        end
      end
    end

    context 'with trusted role' do
      let(:jwt_roles) { 'trusted' }

      context 'without required params' do
        it 'raises a graphql error' do
          expect { client.execute(query) }.to raise_error do |error|
            expect(error).to be_a(Graphlient::Errors::GraphQLError)
          end
        end
      end

      context 'with an order id' do
        let(:order) { Fabricate(:order, state: Order::SUBMITTED) }
        let(:line_item) do
          Fabricate(:line_item, order: order, artwork_id: 'very-wet-painting')
        end

        context 'with an order that is not submitted' do
          let(:order) { Fabricate(:order, state: 'pending') }

          it 'returns an error' do
            expect {
              client.execute(query, orderId: order.id)
            }.to raise_error do |error|
              expect(error).to be_a(Graphlient::Errors::ServerError)
              expect(error.status_code).to eq 400
              expect(error.message).to eq 'the server responded with status 400'
              expect(
                error.response['errors'].first['extensions']['code']
              ).to eq 'order_not_submitted'
              expect(
                error.response['errors'].first['extensions']['type']
              ).to eq 'validation'
            end
          end
        end

        context 'with an order that has no competition' do
          it 'returns an empty array' do
            results = client.execute(query, orderId: order.id)
            expect(results.data.competing_orders.total_count).to eq 0
          end
        end

        context 'with an order that has artwork competition and good params' do
          it 'returns those competing orders' do
            3.times do
              competing_order = Fabricate(:order, state: Order::SUBMITTED)
              Fabricate(
                :line_item,
                order: competing_order, artwork_id: line_item.artwork_id
              )
            end

            results = client.execute(query, orderId: order.id)
            expect(results.data.competing_orders.total_count).to eq 3
          end
        end

        context 'with an order that has edition set competition and good params' do
          let(:line_item) do
            Fabricate(
              :line_item,
              order: order, edition_set_id: 'very-wet-painting'
            )
          end

          it 'returns those competing orders' do
            3.times do
              competing_order = Fabricate(:order, state: Order::SUBMITTED)
              Fabricate(
                :line_item,
                order: competing_order, edition_set_id: line_item.edition_set_id
              )
            end

            results = client.execute(query, orderId: order.id)
            expect(results.data.competing_orders.total_count).to eq 3
          end
        end
      end
    end
  end
end
