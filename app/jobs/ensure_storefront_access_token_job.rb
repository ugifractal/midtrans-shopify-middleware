# frozen_string_literal: true

class EnsureStorefrontAccessTokenJob < ActiveJob::Base
  def perform(shop_domain:)
    shop = Shop.find_by(shopify_domain: shop_domain)

    if shop.nil?
      logger.error("#{self.class} failed: cannot find shop with domain '#{shop_domain}'")
      raise ActiveRecord::RecordNotFound, "Shop Not Found"
    end

    return if shop.storefront_access_token.present?

    session = ShopifyApp::SessionRepository.retrieve_shop_session_by_shopify_domain(shop_domain)
    raise "No session found for shop '#{shop_domain}'" if session.nil?

    Shops::StorefrontAccessToken.ensure!(shop: shop, session: session)
  end
end
