Rails.application.routes.draw do
  root to: "orders#index"
  get "/products", to: "products#index"
  get "/orders", to: "orders#index"
  get "/webhook_setting", to: "webhook_setting#index", as: :webhook_setting
  post "/webhook_setting/recreate", to: "webhook_setting#recreate", as: :recreate_webhooks
  post "/webhook_setting/storefront_token", to: "webhook_setting#rotate_storefront_token", as: :rotate_storefront_token
  post "/webhook_setting/storefront_token/manual", to: "webhook_setting#update_storefront_token", as: :store_storefront_token

  # Custom checkout API reached through the Shopify App Proxy (storefront-relative
  # /apps/midtrans/api/midtrans/checkout/*). Requests are signed with the
  # app secret; see Api::Midtrans::CheckoutController.
  namespace :api do
    namespace :midtrans do
      post "checkout/shipping-rates", to: "checkout#shipping_rates"
      post "checkout/sessions", to: "checkout#sessions"
      # Midtrans HTTP(S) Notification — outbound from Midtrans after a transaction
      # status change, not a Shopify proxy. Verified via signature_key.
      post "hooks", to: "hooks#create"
    end
  end
  mount ShopifyApp::Engine, at: "/"
  mount MissionControl::Jobs::Engine, at: "/admin/jobs"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
