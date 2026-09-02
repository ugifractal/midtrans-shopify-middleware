# frozen_string_literal: true

class Api::Midtrans::CheckoutController < ApplicationController
  include ShopifyApp::AppProxyVerification

  before_action :set_shop
  before_action :ensure_storefront_token

  def shipping_rates
    quote = Midtrans::Quote.call(
      shop: @shop,
      cart_token: payload.fetch(:cart_token),
      shipping_address: payload.fetch(:shipping_address)
    )

    render json: { rates: quote.rates, totals: quote.totals }
  rescue KeyError => e
    render json: { error: "Missing field: #{e.key}" }, status: :bad_request
  rescue Midtrans::Quote::CartNotFoundError, Midtrans::Quote::StorefrontAccessDenied,
         Midtrans::Quote::InvalidCountryError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def sessions
    quote = Midtrans::Quote.call(
      shop: @shop,
      cart_token: payload.fetch(:cart_token),
      shipping_address: payload.fetch(:shipping_address)
    )
    rate = payload.dig(:shipping_rate)

    raise ArgumentError, "Missing shipping_rate" if rate.blank?

    matching = quote.rates.find { |option| option[:handle] == rate[:handle] }
    raise Midtrans::Quote::CartNotFoundError, "Shipping rate no longer available" if matching.nil?
    if matching[:price] != rate[:price].to_i
      raise Midtrans::Quote::CartNotFoundError, "Shipping rate price changed"
    end

    totals = quote.totals.merge(shipping: matching[:price])
    total_amount = quote.totals[:total]
    custom_reference = SecureRandom.hex(16)

    # Snapshot the checkout so the Midtrans notification (which only echoes back
    # order_id + gross_amount + status) can reconstruct the full order details
    # — line items, shipping, totals — without them in the payload.
    MidtransCheckout.create!(
      shop: @shop,
      cart_token: payload.fetch(:cart_token),
      custom_reference: custom_reference,
      customer: payload.fetch(:customer),
      shipping_address: payload.fetch(:shipping_address),
      shipping_rate: { handle: matching[:handle], title: matching[:title], price: matching[:price] },
      totals: totals,
      line_items: quote.line_items,
      total_amount: total_amount,
      currency: quote.totals[:currency],
      status: :pending
    )

    session = Midtrans::Gateway.create_session(
      cart_token: payload.fetch(:cart_token),
      custom_reference: custom_reference,
      customer: payload.fetch(:customer),
      shipping_address: payload.fetch(:shipping_address),
      shipping_rate: { handle: matching[:handle], title: matching[:title], price: matching[:price] },
      totals: totals,
      line_items: quote.line_items,
      total_amount: total_amount,
      currency: quote.totals[:currency]
    )

    render json: { session_id: session.session_id, redirect_url: session.redirect_url }
  rescue KeyError => e
    render json: { error: "Missing field: #{e.key}" }, status: :bad_request
  rescue ArgumentError => e
    render json: { error: e.message }, status: :bad_request
  rescue Midtrans::Quote::CartNotFoundError, Midtrans::Quote::StorefrontAccessDenied,
         Midtrans::Quote::InvalidCountryError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  rescue Midtrans::Gateway::NotConfigured => e
    render json: { error: e.message }, status: :service_unavailable
  rescue Midtrans::Gateway::Error => e
    render json: { error: e.message }, status: :bad_gateway
  end

  private

  def set_shop
    domain = params[:shop].to_s.downcase
    @shop = Shop.find_by(shopify_domain: domain) if domain.present?
    return if @shop

    render json: { error: "Unknown shop" }, status: :not_found
  end

  # Creates the per-shop storefront token on demand so the proxy endpoints work
  # even before the install-time job has run (or re-auth has happened). Failures
  # fall through so Midtrans::Quote raises the friendly 422.
  def ensure_storefront_token
    return if @shop.storefront_access_token.present?

    session = ShopifyApp::SessionRepository.retrieve_shop_session_by_shopify_domain(@shop.shopify_domain)
    Shops::StorefrontAccessToken.ensure!(shop: @shop, session: session) if session
  rescue StandardError
    nil
  end

  # Shopify App Proxy forwards the request body and appends its own query params
  # (shop/signature); parse the raw body so it never confuses the two.
  def payload
    @payload ||= JSON.parse(request.raw_post).deep_symbolize_keys
  rescue JSON::ParserError, TypeError
    {}
  end

  # Public API reached via Shopify's proxied fetcher, not a browser.
  def allow_browser(versions:, block:)
    nil
  end
end
