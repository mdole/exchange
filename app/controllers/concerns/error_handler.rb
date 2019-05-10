module ErrorHandler
  def self.included(clazz)
    clazz.class_eval do
      rescue_from StandardError do |exception|
        capture_exception(exception)
        log_exception(exception)
        render json: {
                 errors: [
                   Types::ApplicationErrorType.root_level_error_from_exception(
                     exception
                   )
                 ]
               },
               status: :internal_server_error
      end

      rescue_from ActionController::ParameterMissing do |exception|
        log_exception(exception)
        render json: {
                 errors: [
                   Types::ApplicationErrorType.format_error_type(
                     type: :validation,
                     code: :missing_param,
                     data: { field: exception.param }
                   )
                 ]
               },
               status: :bad_request
      end

      rescue_from ActiveRecord::RecordNotFound do |exception|
        log_exception(exception)
        render json: {
                 errors: [
                   Types::ApplicationErrorType.format_root_level_error(
                     type: :validation,
                     code: :not_found,
                     data: { message: exception.to_s }
                   )
                 ]
               },
               status: :not_found
      end

      rescue_from Errors::ValidationError do |exception|
        log_exception(exception)
        render json: {
                 errors: [
                   Types::ApplicationErrorType
                     .root_level_from_application_error(exception)
                 ]
               },
               status: :bad_request
      end
    end
  end

  private

  def log_exception(exception)
    Rails.logger.error(exception.message)
    trace = exception.backtrace.join("\n")
    Rails.logger.error(trace)
  end
end
