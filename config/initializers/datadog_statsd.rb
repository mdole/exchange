module Datadog
  module StatsdDisabled
    attr_accessor :disabled

    def send_to_socket(message)
      print message
      super unless disabled
    end
  end
end

Datadog::Statsd.prepend Datadog::StatsdDisabled

module Exchange
  def self.dogstatsd
    @dogstatsd ||= build_statsd
  end

  def self.build_statsd
    hostname = ENV.fetch('DATADOG_TRACE_AGENT_HOSTNAME', 'localhost')
    port = 8125
    tags = ['service:exchange']
    dogstatsd = Datadog::Statsd.new(hostname, port, tags: tags)
    dogstatsd.disabled = ENV['DATADOG_ENABLED'] != 'true'
    dogstatsd
  end
end
