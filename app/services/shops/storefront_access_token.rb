# frozen_string_literal: true

module Shops
  # Manages the per-shop Storefront API access token used by the custom checkout
  # to quote cart costs/shipping via the Storefront Cart API.
  class StorefrontAccessToken
    TITLE = "Midtrans Checkout"

    class << self
      def ensure!(shop:, session:)
        return shop.storefront_access_token if shop.storefront_access_token.present?

        token = create!(session: session)
        shop.update!(storefront_access_token: token.access_token, storefront_access_token_id: token.id)
        shop.storefront_access_token
      end

      def rotate!(shop:, session:)
        destroy_existing!(shop: shop, session: session)
        token = create!(session: session)
        shop.update!(storefront_access_token: token.access_token, storefront_access_token_id: token.id)
        shop.storefront_access_token
      end

      def store_manual!(shop:, token:, token_id: nil)
        value = token.to_s.strip
        raise "Storefront access token cannot be blank" if value.blank?

        shop.update!(storefront_access_token: value, storefront_access_token_id: token_id.presence)
        shop.storefront_access_token
      end

      private

      def create!(session:)
        instance = ShopifyAPI::StorefrontAccessToken.new(session: session, from_hash: { title: TITLE })
        instance.save!
        raise "Storefront access token response is missing access_token" if instance.access_token.blank?

        instance
      end

      def destroy_existing!(shop:, session:)
        existing = ShopifyAPI::StorefrontAccessToken.all(session: session)
                             .find { |token| token.id == shop.storefront_access_token_id }
        existing&.delete
      end
    end
  end
end
