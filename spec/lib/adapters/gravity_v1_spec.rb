require 'rails_helper'

describe Adapters::GravityV1 do
  it 'raises Gravity Error when get 404' do
    stub_request(:get, /artwork/).to_return(
      status: 404, body: { error: 'cannot find' }.to_json
    )
    expect { Adapters::GravityV1.get('artwork/2') }.to raise_error(
      Adapters::GravityError
    )
  end
end
