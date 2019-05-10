module Api
  class HealthController < Api::BaseApiController
    skip_before_action :authenticate_request!
    SIDEKIQ_ALERT_THRESHOLD = 100

    def index
      sidekiq_default_queue_size = Sidekiq::Queue.new.size
      render json: {
               api_healthy: true,
               worker_health:
                 if sidekiq_default_queue_size < SIDEKIQ_ALERT_THRESHOLD
                   'OK'
                 else
                   'OY'
                 end,
               worker_default_queue_size: sidekiq_default_queue_size
             }
    end
  end
end
