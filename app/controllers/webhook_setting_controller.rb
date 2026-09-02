# frozen_string_literal: true

class WebhookSettingController < AuthenticatedController
  WEBHOOKS_QUERY = <<~GRAPHQL
    {
      webhookSubscriptions(first: 100) {
        edges {
          node {
            id
            topic
            format
            includeFields
            metafieldNamespaces
            filter
            endpoint {
              __typename
              ... on WebhookHttpEndpoint {
                callbackUrl
              }
            }
          }
        }
      }
    }
  GRAPHQL

  def index
    client = ShopifyAPI::Clients::Graphql::Admin.new(session: current_shopify_session)
    response = client.query(query: WEBHOOKS_QUERY, response_as_struct: false)
    @webhooks = response.body.dig("data", "webhookSubscriptions", "edges").map { |edge| edge["node"] }
  rescue ShopifyAPI::Errors::HttpResponseError => e
    flash.now[:alert] = "Failed to load webhooks: #{e.message}"
    @webhooks = []
  end

  def recreate
    ShopifyApp::WebhooksManager.recreate_webhooks!(session: current_shopify_session)
    redirect_to webhook_setting_path, notice: "Webhooks recreated successfully"
  rescue ShopifyAPI::Errors::HttpResponseError, ShopifyAPI::Errors::WebhookRegistrationError => e
    redirect_to webhook_setting_path, alert: "Failed to recreate webhooks: #{e.message}"
  end

  def rotate_storefront_token
    Shops::StorefrontAccessToken.rotate!(shop: current_shop, session: current_shopify_session)
    redirect_to webhook_setting_path, notice: "Storefront access token created successfully"
  rescue ShopifyAPI::Errors::HttpResponseError => e
    redirect_to webhook_setting_path, alert: "Failed to create storefront access token: #{e.message}"
  end

  def update_storefront_token
    Shops::StorefrontAccessToken.store_manual!(
      shop: current_shop,
      token: params[:storefront_access_token],
      token_id: params[:storefront_access_token_id]
    )
    redirect_to webhook_setting_path, notice: "Storefront access token saved"
  rescue StandardError => e
    redirect_to webhook_setting_path, alert: "Failed to save storefront access token: #{e.message}"
  end
end
