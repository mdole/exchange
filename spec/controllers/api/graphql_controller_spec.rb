require 'rails_helper'

describe Api::GraphqlController, type: :request do
  describe '@POST #api/graphql' do
    let(:query) { GraphQL::Introspection::INTROSPECTION_QUERY }

    context 'unauthorized' do
      it 'raises error when there is no header' do
        post '/api/graphql', params: { query: query }
        expect(response.status).to eq 401
      end
      it 'raises error when unknown jwt' do
        post '/api/graphql',
             params: { query: query },
             headers: { 'Authorization' => 'Bearer: random-token' }
        expect(response.status).to eq 401
      end
    end

    context 'authorized' do
      let(:headers) do
        jwt_headers(user_id: 'user_id', partner_ids: %w[partner_id])
      end
      it 'returns schema' do
        post '/api/graphql', params: { query: query }, headers: headers
        expect(response.status).to eq 200
        response_body = JSON.parse(response.body, symbolize_names: true)
        expect(response_body.dig(:data, :__schema)).not_to be_nil
      end
    end
  end
end
