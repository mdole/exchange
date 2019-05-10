class Types::ApplicationErrorType < Types::BaseObject
  description 'An generic error type for mutations'
  graphql_name 'ApplicationError'

  field :code, String, null: false, description: 'Code of this error'
  field :data, String, null: true, description: 'What caused the error'
  field :type, String, null: false, description: 'Type of this error'

  def self.from_application(err)
    format_error_type(type: err.type, code: err.code, data: err.data.to_json)
  end

  def self.format_error_type(type:, code:, data: nil)
    { code: code, data: data, type: type }
  end

  def self.root_level_from_application_error(err)
    format_root_level_error(type: err.type, code: err.code, data: err.data)
  end

  def self.root_level_error_from_exception(err)
    format_root_level_error(
      type: :internal,
      code: :generic,
      data: { message: err.message },
      message: err.message
    )
  end

  # For root level errors expect a message key and our detail data should be under extension
  def self.format_root_level_error(type:, code:, data: nil, message: nil)
    message ||= "type: #{type}, code: #{code}, data: #{data}"

    {
      message: message,
      extensions: format_error_type(type: type, code: code, data: data)
    }
  end
end
