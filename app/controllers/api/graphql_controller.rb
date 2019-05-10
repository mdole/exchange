module Api
  class GraphqlController < Api::BaseApiController
    def execute
      variables = ensure_hash(params[:variables])
      query = params[:query]
      operation_name = params[:operationName]
      context = {
        # Query context goes here, for example:
        current_user: current_user,
        user_agent: request.headers['User-Agent'],
        user_ip: request.headers['x-forwarded-for']
      }
      result =
        ExchangeSchema.execute(
          query,
          variables: variables, context: context, operation_name: operation_name
        )
      render json: result
    end

    private

    # Handle form data, JSON body, or a blank value
    def ensure_hash(ambiguous_param)
      case ambiguous_param
      when String
        ambiguous_param.present? ? ensure_hash(JSON.parse(ambiguous_param)) : {}
      when Hash, ActionController::Parameters
        ambiguous_param
      when nil
        {}
      else
        raise ArgumentError, "Unexpected parameter: #{ambiguous_param}"
      end
    end
  end
end
