# frozen_string_literal: true

Datadog.configure do |c|
  enabled = ENV['DATADOG_ENABLED'] == 'true' && !defined?(Rails::Console)
  hostname = ENV.fetch('DATADOG_TRACE_AGENT_HOSTNAME', 'localhost')
  debug = ENV['DATADOG_DEBUG'] == 'true'

  c.tracer enabled: enabled,
           hostname: hostname,
           distributed_tracing: true,
           debug: debug
  c.use :rails,
        service_name: 'exchange',
        distributed_tracing: true,
        controller_service: 'exchange.controller',
        cache_service: 'exchange.cache',
        database_service: 'exchange.postgres'
  c.use :graphql, service_name: 'exchange.graphql', schemas: [ExchangeSchema]
  c.use :redis, service_name: 'exchange.redis'
  c.use :sidekiq, service_name: 'exchange.sidekiq'
  c.use :http, service_name: 'exchange.http', distributed_tracing: true
end
