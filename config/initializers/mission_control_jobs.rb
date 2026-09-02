# frozen_string_literal: true

Rails.application.configure do
  config.after_initialize do
    MissionControl::Jobs.http_basic_auth_user = ENV.fetch("MISSION_CONTROL_USER", "admin")
    MissionControl::Jobs.http_basic_auth_password = ENV["MISSION_CONTROL_PASSWORD"]
    MissionControl::Jobs.filter_arguments = [ :shopify_token, :token, :api_key, :secret, :email, :phone ]
  end
end
