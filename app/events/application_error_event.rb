class ApplicationErrorEvent < Events::BaseEvent
  TOPIC = 'commerce'.freeze
  ACTIONS = [RAISED = 'raised'.freeze].freeze

  def initialize(application_error)
    super(user: nil, action: RAISED, model: application_error)
  end

  def object
    { id: @object.class, display: @object.to_s }
  end

  def properties
    {
      type: @object.type,
      code: @object.code,
      created_at: Time.now.utc,
      data: @object.data
    }
  end

  def routing_key
    "error.#{@object.type}.#{@object.code}"
  end
end
