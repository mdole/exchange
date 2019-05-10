require 'rails_helper'
require 'support/use_stripe_mock'

describe Api::GraphqlController, type: :request do
  include_context 'use stripe mock'
  include_context 'GraphQL Client'
  describe 'fix_failed_payment mutation' do
    let(:seller_id) { jwt_partner_ids.first }
    let(:user_id) { jwt_user_id }
    let(:credit_card_id) { 'gravity-cc-1' }
    let(:credit_card) do
      {
        id: credit_card_id,
        user: { _id: user_id },
        external_id: stripe_customer.default_source,
        customer_account: { external_id: stripe_customer.id }
      }
    end
    let(:state) { Order::SUBMITTED }
    let(:merchant_account) { { external_id: 'ma-1' } }
    let(:order) do
      Fabricate(
        :order,
        seller_id: seller_id,
        buyer_id: user_id,
        state: state,
        credit_card_id: 'bad-cc',
        shipping_name: 'Fname Lname',
        shipping_address_line1: '12 Vanak St',
        shipping_address_line2: 'P 80',
        shipping_city: 'Tehran',
        shipping_postal_code: '02198',
        buyer_phone_number: '00123456',
        shipping_country: 'IR',
        fulfillment_type: Order::SHIP,
        items_total_cents: 1000_00,
        seller_type: 'gallery',
        buyer_type: 'user'
      )
    end
    let(:transaction_status) { Transaction::FAILURE }
    let(:transaction) do
      Fabricate(:transaction, order: order, status: transaction_status)
    end
    let!(:line_item) do
      Fabricate(
        :line_item,
        order: order,
        list_price_cents: 1000_00,
        artwork_id: 'a-1',
        artwork_version_id: '1'
      )
    end
    let(:offer) do
      Fabricate(
        :offer,
        order: order,
        from_id: seller_id,
        from_type: 'gallery',
        amount_cents: 800_00,
        shipping_total_cents: 100_00,
        tax_total_cents: 300_00
      )
    end
    let(:artwork) { { _id: 'a-1', current_version_id: '1' } }

    let(:mutation) do
      <<-GRAPHQL
        mutation($input: FixFailedPaymentInput!) {
          fixFailedPayment(input: $input) {
            orderOrError {
              ... on OrderWithMutationSuccess {
                order {
                  id
                  state
                  creditCardId
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

    let(:mutation_input) do
      { input: { offerId: offer.id.to_s, creditCardId: credit_card_id } }
    end
    before(:each) do
      order.transactions << transaction
      order.update!(
        last_offer: offer,
        buyer_total_cents: offer.buyer_total_cents,
        shipping_total_cents: offer.shipping_total_cents
      )
    end
    context 'with user without permission to this order' do
      let(:user_id) { 'random-user-id-on-another-order' }
      it 'returns permission error' do
        response = client.execute(mutation, mutation_input)
        expect(
          response.data.fix_failed_payment.order_or_error.error.type
        ).to eq 'validation'
        expect(
          response.data.fix_failed_payment.order_or_error.error.code
        ).to eq 'not_found'
        expect(order.reload.state).to eq Order::SUBMITTED
        expect(order.reload.credit_card_id).to eq 'bad-cc'
      end
    end

    context 'with proper permission' do
      context 'with order in APPROVED state' do
        let(:state) { Order::APPROVED }
        it 'returns error' do
          response = client.execute(mutation, mutation_input)
          expect(
            response.data.fix_failed_payment.order_or_error.error.type
          ).to eq 'validation'
          expect(
            response.data.fix_failed_payment.order_or_error.error.code
          ).to eq 'invalid_state'
          expect(order.reload.state).to eq Order::APPROVED
          expect(order.reload.credit_card_id).to eq 'bad-cc'
        end
      end

      context 'with order in PENDING state' do
        let(:state) { Order::PENDING }
        it 'returns error' do
          response = client.execute(mutation, mutation_input)
          expect(
            response.data.fix_failed_payment.order_or_error.error.type
          ).to eq 'validation'
          expect(
            response.data.fix_failed_payment.order_or_error.error.code
          ).to eq 'invalid_state'
          expect(order.reload.state).to eq Order::PENDING
          expect(order.reload.credit_card_id).to eq 'bad-cc'
        end
      end

      context 'with last_transaction_failed? == false' do
        let(:transaction_status) { Transaction::SUCCESS }
        it 'returns error' do
          response = client.execute(mutation, mutation_input)
          expect(
            response.data.fix_failed_payment.order_or_error.error.type
          ).to eq 'validation'
          expect(
            response.data.fix_failed_payment.order_or_error.error.code
          ).to eq 'invalid_state'
          expect(order.reload.state).to eq Order::SUBMITTED
          expect(order.reload.credit_card_id).to eq 'bad-cc'
        end
      end

      context 'with last_transaction_failed? == true' do
        context 'with a credit card that does not belong to the buyer' do
          let(:invalid_credit_card) do
            { id: credit_card_id, user: { _id: 'someone_else' } }
          end
          it 'raises an error' do
            expect(Gravity).to receive(:get_credit_card).with(credit_card_id)
              .and_return(invalid_credit_card)
            response = client.execute(mutation, mutation_input)
            expect(
              response.data.fix_failed_payment.order_or_error.error.type
            ).to eq 'validation'
            expect(
              response.data.fix_failed_payment.order_or_error.error.code
            ).to eq 'invalid_credit_card'
            expect(order.reload.credit_card_id).to eq 'bad-cc'
          end
        end

        context 'with a credit card that belongs to the buyer' do
          context 'with proper permission' do
            let(:deduct_inventory_request) do
              stub_request(
                :put,
                "#{
                  Rails.application.config_for(:gravity)['api_v1_root']
                }/artwork/a-1/inventory"
              )
                .with(body: { deduct: 1 })
                .to_return(status: 200, body: {}.to_json)
            end
            let(:undeduct_inventory_request) do
              stub_request(
                :put,
                "#{
                  Rails.application.config_for(:gravity)['api_v1_root']
                }/artwork/a-1/inventory"
              )
                .with(body: { undeduct: 1 })
                .to_return(status: 200, body: {}.to_json)
            end
            let(:credit_card_request) do
              stub_request(
                :get,
                "#{
                  Rails.application.config_for(:gravity)['api_v1_root']
                }/credit_card/#{credit_card_id}"
              )
                .to_return(status: 200, body: credit_card.to_json)
            end
            let(:artwork_request) do
              stub_request(
                :get,
                "#{
                  Rails.application.config_for(:gravity)['api_v1_root']
                }/artwork/a-1"
              )
                .to_return(status: 200, body: artwork.to_json)
            end
            let(:merchant_account_request) do
              stub_request(
                :get,
                "#{
                  Rails.application.config_for(:gravity)['api_v1_root']
                }/merchant_accounts"
              )
                .with(query: { partner_id: seller_id })
                .to_return(status: 200, body: [merchant_account].to_json)
            end
            let(:partner_account_request) do
              stub_request(
                :get,
                "#{
                  Rails.application.config_for(:gravity)['api_v1_root']
                }/partner/#{seller_id}/all"
              )
                .to_return(status: 200, body: gravity_v1_partner.to_json)
            end
            before do
              deduct_inventory_request
              merchant_account_request
              credit_card_request
              artwork_request
              partner_account_request
            end

            context 'with failed stripe charge' do
              before do
                undeduct_inventory_request
                StripeMock.prepare_card_error(:card_declined)
              end

              it 'raises processing error' do
                response = client.execute(mutation, mutation_input)
                expect(
                  response.data.fix_failed_payment.order_or_error.error.code
                ).to eq 'capture_failed'
              end

              it 'stores failed transaction' do
                expect { client.execute(mutation, mutation_input) }.to change(
                  order.transactions.where(status: Transaction::FAILURE),
                  :count
                )
                  .by(1)
                expect(order.reload.external_charge_id).to be_nil
                expect(order.transactions.last.failed?).to be true
                expect(order.last_transaction_failed?).to be true
              end

              it 'undeducts inventory' do
                client.execute(mutation, mutation_input)
                expect(undeduct_inventory_request).to have_been_requested
              end
            end

            it 'approves the order' do
              response = client.execute(mutation, mutation_input)

              expect(
                response.data.fix_failed_payment.order_or_error
              ).to respond_to(:order)

              expect(deduct_inventory_request).to have_been_requested

              expect(
                response.data.fix_failed_payment.order_or_error.order
              ).not_to be_nil

              response_order =
                response.data.fix_failed_payment.order_or_error.order
              expect(response_order.id).to eq order.id.to_s
              expect(response_order.state).to eq Order::APPROVED.upcase

              expect(
                response.data.fix_failed_payment.order_or_error
              ).not_to respond_to(:error)
              expect(order.reload.state).to eq Order::APPROVED
              expect(order.state_updated_at).not_to be_nil
              expect(order.state_expires_at).to eq(
                order.state_updated_at + 7.days
              )
              expect(order.reload.transactions.last.external_id).not_to be_nil
              expect(
                order.reload.transactions.order(updated_at: 'asc').last
                  .transaction_type
              ).to eq Transaction::CAPTURE
            end

            context 'with offer from buyer' do
              let(:offer) do
                Fabricate(
                  :offer,
                  order: order,
                  from_id: user_id,
                  from_type: 'user',
                  amount_cents: 800_00,
                  shipping_total_cents: 100_00,
                  tax_total_cents: 300_00
                )
              end
              it 'approves the order' do
                response = client.execute(mutation, mutation_input)

                expect(
                  response.data.fix_failed_payment.order_or_error
                ).to respond_to(:order)

                expect(deduct_inventory_request).to have_been_requested

                expect(
                  response.data.fix_failed_payment.order_or_error.order
                ).not_to be_nil

                response_order =
                  response.data.fix_failed_payment.order_or_error.order
                expect(response_order.id).to eq order.id.to_s
                expect(response_order.state).to eq Order::APPROVED.upcase

                expect(
                  response.data.fix_failed_payment.order_or_error
                ).not_to respond_to(:error)
                expect(order.reload.state).to eq Order::APPROVED
                expect(order.state_updated_at).not_to be_nil
                expect(order.state_expires_at).to eq(
                  order.state_updated_at + 7.days
                )
                expect(order.reload.transactions.last.external_id).not_to be_nil
                expect(
                  order.reload.transactions.order(updated_at: 'asc').last
                    .transaction_type
                ).to eq Transaction::CAPTURE
              end
            end

            it 'sets payments on the order' do
              response = client.execute(mutation, mutation_input)
              expect(
                response.data.fix_failed_payment.order_or_error.order.id
              ).to eq order.id.to_s
              expect(
                response.data.fix_failed_payment.order_or_error.order.state
              ).to eq 'APPROVED'
              expect(
                response.data.fix_failed_payment.order_or_error.order
                  .credit_card_id
              ).to eq 'gravity-cc-1'
              expect(
                response.data.fix_failed_payment.order_or_error
              ).not_to respond_to(:error)
              expect(order.reload.credit_card_id).to eq credit_card_id
              expect(order.state).to eq Order::APPROVED
            end
          end
        end
      end
    end
  end
end
