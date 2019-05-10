require 'json'
require 'taxjar'
require 'webmock/rspec'

def stub_tax_for_order
  stub_request(:post, Taxjar::API::Request::DEFAULT_API_URL + '/v2/taxes')
    .to_return(
    body: sales_tax_fixture.to_json,
    headers: { content_type: 'application/json; charset=utf-8' }
  )
  stub_request(
    :post,
    Taxjar::API::Request::DEFAULT_API_URL + '/v2/transactions/orders'
  )
    .to_return(
    body: order_fixture.to_json,
    headers: { content_type: 'application/json; charset=utf-8' }
  )
end

def order_fixture
  {
    "order": {
      "transaction_id": '123',
      "user_id": 10_649,
      "transaction_date": '2015-05-14T00:00:00Z',
      "from_country": 'US',
      "from_zip": '93107',
      "from_state": 'CA',
      "from_city": 'SANTA BARBARA',
      "from_street": '1281 State St',
      "to_country": 'US',
      "to_zip": '90002',
      "to_state": 'CA',
      "to_city": 'LOS ANGELES',
      "to_street": '123 Palm Grove Ln',
      "amount": '17.45',
      "shipping": '1.5',
      "sales_tax": '0.95',
      "line_items": [
        {
          "id": '1',
          "quantity": 1,
          "product_identifier": '12-34243-9',
          "description": 'Fuzzy Widget',
          "product_tax_code": '20010',
          "unit_price": '15.0',
          "discount": '0.0',
          "sales_tax": '0.95'
        }
      ]
    }
  }
end

def sales_tax_fixture
  {
    "tax": {
      "order_total_amount": 16.5,
      "shipping": 1.5,
      "taxable_amount": 16.5,
      "amount_to_collect": 1.16,
      "rate": 0.07,
      "has_nexus": true,
      "freight_taxable": true,
      "tax_source": 'destination',
      "breakdown": {
        "taxable_amount": 16.5,
        "tax_collectable": 1.16,
        "combined_tax_rate": 0.07,
        "state_taxable_amount": 16.5,
        "state_tax_rate": 0.07,
        "state_tax_collectable": 1.16,
        "county_taxable_amount": 0,
        "county_tax_rate": 0,
        "county_tax_collectable": 0,
        "city_taxable_amount": 0,
        "city_tax_rate": 0,
        "city_tax_collectable": 0,
        "special_district_taxable_amount": 0,
        "special_tax_rate": 0,
        "special_district_tax_collectable": 0,
        "shipping": {
          "taxable_amount": 1.5,
          "tax_collectable": 0.11,
          "combined_tax_rate": 0.07,
          "state_taxable_amount": 1.5,
          "state_sales_tax_rate": 0.07,
          "state_amount": 0.11,
          "county_taxable_amount": 0,
          "county_tax_rate": 0,
          "county_amount": 0,
          "city_taxable_amount": 0,
          "city_tax_rate": 0,
          "city_amount": 0,
          "special_taxable_amount": 0,
          "special_tax_rate": 0,
          "special_district_amount": 0
        },
        "line_items": [
          {
            "id": '1',
            "taxable_amount": 15,
            "tax_collectable": 1.05,
            "combined_tax_rate": 0.07,
            "state_taxable_amount": 15,
            "state_sales_tax_rate": 0.07,
            "state_amount": 1.05,
            "county_taxable_amount": 0,
            "county_tax_rate": 0,
            "county_amount": 0,
            "city_taxable_amount": 0,
            "city_tax_rate": 0,
            "city_amount": 0,
            "special_district_taxable_amount": 0,
            "special_tax_rate": 0,
            "special_district_amount": 0
          }
        ]
      }
    }
  }
end
