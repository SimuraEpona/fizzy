Rails.application.configure do |config|
  # uuugh this resolver proc is so gross.
  config.middleware.use ActiveRecord::Tenanted::TenantSelector, "ApplicationRecord", ->(request) { request.subdomain.split(".").first }
end

ActiveSupport.on_load(:action_controller_base) do
  before_action { logger.struct tenant: ApplicationRecord.current_tenant }
end
