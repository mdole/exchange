require 'graphlient'

RSpec.shared_context 'GraphQL Client', shared_context: :metadata do
  let(:jwt_user_id) { 'user-id' }
  let(:jwt_partner_ids) { %w[partner-id] }
  let(:jwt_roles) { 'user' }
  let(:auth_headers) do
    jwt_headers(
      user_id: jwt_user_id, partner_ids: jwt_partner_ids, roles: jwt_roles
    )
  end
  let(:user_agent) { 'user-agent' }
  let(:user_ip) { 'user-ip' }
  let(:analytics_headers) do
    { 'User-Agent' => user_agent, 'x-forwarded-for' => user_ip }
  end
  let(:headers) { auth_headers.merge(analytics_headers) }
  let(:client) do
    Graphlient::Client.new(
      'http://localhost:4000/api/graphql',
      headers: headers
    ) do |client|
      client.http { |h| h.connection { |c| c.use Faraday::Adapter::Rack, app } }
    end
  end
end
