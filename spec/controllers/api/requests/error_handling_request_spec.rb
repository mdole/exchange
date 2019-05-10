require 'rails_helper'

describe Api::GraphqlController, type: :request do
  describe 'ErrorType' do
    let(:auth_headers) do
      jwt_headers(user_id: 'user-id', partner_ids: %w[p1], roles: nil)
    end
    let(:mutation_input) { { artworkId: 'test' } }
    let(:mutation) do
      <<-GRAPHQL
        mutation($input: CreateOrderWithArtworkInput!) {
          createOrderWithArtwork(input: $input) {
            orderOrError {
              ... on OrderWithMutationSuccess {
                order {
                  id
                  buyer {
                    ... on Partner {
                      id
                    }
                  }
                  seller {
                    ... on User {
                      id
                    }
                  }
                }
              }
              ... on OrderWithMutationFailure {
                error {
                  code
                  data
                  type
                }
              }
            }
          }
        }
      GRAPHQL
    end

    context 'StandardError' do
      before do
        expect(OrderService).to receive(:create_with_artwork!).and_raise(
          'something went wrong'
        )
        post '/api/graphql',
             params: { query: mutation, variables: { input: mutation_input } },
             headers: auth_headers
      end
      it 'returns 500' do
        expect(response.status).to eq 500
      end
      it 'returns formatted the error' do
        result = JSON.parse(response.body)
        expect(result['errors']).not_to be_nil
        error = result['errors'].first
        expect(error['message']).to eq 'something went wrong'
        expect(error['extensions']['type']).to eq 'internal'
        expect(error['extensions']['code']).to eq 'generic'
        expect(
          error['extensions']['data']['message']
        ).to eq 'something went wrong'
      end
    end

    context 'ActiveRecord::RecordNotFound' do
      before do
        expect(OrderService).to receive(:create_with_artwork!).and_raise(
          ActiveRecord::RecordNotFound,
          'cannot find'
        )
        post '/api/graphql',
             params: { query: mutation, variables: { input: mutation_input } },
             headers: auth_headers
      end
      it 'returns 404' do
        expect(response.status).to eq 404
      end
      it 'returns formatted the error' do
        result = JSON.parse(response.body)
        expect(result['errors']).not_to be_nil
        error = result['errors'].first
        expect(
          error['message']
        ).to eq 'type: validation, code: not_found, data: {:message=>"cannot find"}'
        expect(error['extensions']['type']).to eq 'validation'
        expect(error['extensions']['code']).to eq 'not_found'
        expect(error['extensions']['data']['message']).to eq 'cannot find'
      end
    end

    context 'ActionController::ParameterMissing' do
      before do
        expect(OrderService).to receive(:create_with_artwork!).and_raise(
          ActionController::ParameterMissing,
          'id'
        )
        post '/api/graphql',
             params: { query: mutation, variables: { input: mutation_input } },
             headers: auth_headers
      end
      it 'returns 400' do
        expect(response.status).to eq 400
      end
      it 'returns formatted the error' do
        result = JSON.parse(response.body)
        expect(result['errors']).not_to be_nil
        error = result['errors'].first
        expect(error['type']).to eq 'validation'
        expect(error['code']).to eq 'missing_param'
        expect(error['data']['field']).to eq 'id'
      end
    end
  end
end
