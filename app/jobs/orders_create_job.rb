# frozen_string_literal: true

class OrdersCreateJob < ActiveJob::Base
  extend ShopifyAPI::Webhooks::WebhookHandler

  def self.handle(topic:, shop:, body:, webhook_id:, api_version:)
    perform_later(topic: topic, shop_domain: shop, webhook: body)
  end

  def perform(topic:, shop_domain:, webhook:)
    shop = Shop.find_by(shopify_domain: shop_domain)

    if shop.nil?
      logger.error("#{self.class} failed: cannot find shop with domain '#{shop_domain}'")

      raise ActiveRecord::RecordNotFound, "Shop Not Found"
    end

    order = Order.find_or_initialize_by(shopify_order_id: webhook["id"])
    order.shop = shop
    order.assign_attributes(
      name: webhook["name"],
      total_price: webhook["total_price"],
      currency: webhook["currency"],
      financial_status: webhook["financial_status"],
      fulfillment_status: webhook["fulfillment_status"],
      placed_at: webhook["created_at"],
      raw_payload: webhook,
    )
    order.save!
  end
end
