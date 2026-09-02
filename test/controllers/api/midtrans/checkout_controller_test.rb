# frozen_string_literal: true

require "test_helper"

class Api::Midtrans::CheckoutControllerTest < ActionDispatch::IntegrationTest
  setup do
    ShopifyApp.configuration.secret = "test-secret"
    shops(:regular_shop).update!(storefront_access_token: "shpat_test_token", storefront_access_token_id: 1)
  end

  test "shipping_rates returns quoted rates and totals from Shopify" do
    quote = Midtrans::Quote::Result.new(
      rates: [ { handle: "standard", title: "Standard Shipping", price: 900, currency: "IDR" } ],
      totals: { currency: "IDR", subtotal: 5000, discount: 250, total: 5250 }
    )

    Midtrans::Quote.stub(:call, ->(**) { quote }) do
      post signed_path("/api/midtrans/checkout/shipping-rates"),
        params: body_json, headers: { "CONTENT_TYPE" => "application/json" }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Standard Shipping", body.dig("rates", 0, "title")
    assert_equal 900, body.dig("rates", 0, "price")
    assert_equal 5250, body.dig("totals", "total")
  end

  test "shipping_rates forwards cart token and shipping address to the quote" do
    captured = nil
    Midtrans::Quote.stub(:call, ->(shop:, cart_token:, shipping_address:) {
      captured = [ shop.shopify_domain, cart_token, shipping_address ]
      Midtrans::Quote::Result.new(rates: [], totals: { currency: "IDR", subtotal: 0, discount: 0, total: 0 })
    }) do
      post signed_path("/api/midtrans/checkout/shipping-rates"),
        params: body_json, headers: { "CONTENT_TYPE" => "application/json" }
    end

    assert_response :success
    assert_equal "regular-shop.myshopify.com", captured[0]
    assert_equal "abc123", captured[1]
    assert_equal "Canada", captured[2][:country]
  end

  test "shipping_rates requires a valid signature" do
    ShopifyApp.configuration.secret = "other-secret"
    post signed_path("/api/midtrans/checkout/shipping-rates", secret: "test-secret"),
      params: body_json, headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :forbidden
  end

  test "shipping_rates rejects a request without a signature" do
    unsigned = { shop: "regular-shop.myshopify.com", path_prefix: "/apps/midtrans", timestamp: "1750000000" }
    post "/api/midtrans/checkout/shipping-rates?#{unsigned.to_query}",
      params: body_json, headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :forbidden
  end

  test "shipping_rates returns 404 for an unknown shop" do
    post signed_path("/api/midtrans/checkout/shipping-rates", shop: "unknown-shop.myshopify.com"),
      params: body_json, headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :not_found
  end

  test "shipping_rates reports storefront token problems" do
    Midtrans::Quote.stub(:call, ->(**) { raise Midtrans::Quote::StorefrontAccessDenied, "Storefront access token is missing" }) do
      post signed_path("/api/midtrans/checkout/shipping-rates"),
        params: body_json, headers: { "CONTENT_TYPE" => "application/json" }
    end

    assert_response :unprocessable_entity
    assert_match(/Storefront access token is missing/, response.body)
  end

  test "sessions creates a midtrans session with server-side totals" do
    quote = Midtrans::Quote::Result.new(
      rates: [ { handle: "standard", title: "Standard Shipping", price: 900, currency: "IDR" } ],
      totals: { currency: "IDR", subtotal: 5000, discount: 250, shipping: 900, total: 5650 }
    )
    session = Midtrans::Gateway::Session.new(
      session_id: "sess_1", redirect_url: "https://app.sandbox.midtrans.com/snap/v2/vtweb/abc"
    )

    Midtrans::Quote.stub(:call, ->(**) { quote }) do
      Midtrans::Gateway.stub(:create_session, ->(payload) { session }) do
        post signed_path("/api/midtrans/checkout/sessions"),
          params: body_json(rate: { handle: "standard", title: "Standard Shipping", price: 900 }),
          headers: { "CONTENT_TYPE" => "application/json" }
      end
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "sess_1", body["session_id"]
    assert_equal "https://app.sandbox.midtrans.com/snap/v2/vtweb/abc", body["redirect_url"]
  end

  test "sessions sends total_amount equal to the grand total (shipping counted once)" do
    quote = Midtrans::Quote::Result.new(
      rates: [ { handle: "standard", title: "Standard Shipping", price: 900, currency: "IDR" } ],
      totals: { currency: "IDR", subtotal: 5000, discount: 250, shipping: 900, total: 5650 }
    )
    session = Midtrans::Gateway::Session.new(
      session_id: "sess_1", redirect_url: "https://app.sandbox.midtrans.com/snap/v2/vtweb/abc"
    )
    captured = nil

    Midtrans::Quote.stub(:call, ->(**) { quote }) do
      Midtrans::Gateway.stub(:create_session, ->(payload) { captured = payload; session }) do
        post signed_path("/api/midtrans/checkout/sessions"),
          params: body_json(rate: { handle: "standard", title: "Standard Shipping", price: 900 }),
          headers: { "CONTENT_TYPE" => "application/json" }
      end
    end

    assert_response :success
    assert_equal 5650, captured[:total_amount]
    assert_equal captured[:totals][:total], captured[:total_amount]
    assert_equal 900, captured[:totals][:shipping]
  end

  test "sessions rejects a tampered shipping rate price" do
    quote = Midtrans::Quote::Result.new(
      rates: [ { handle: "standard", title: "Standard Shipping", price: 900, currency: "IDR" } ],
      totals: { currency: "IDR", subtotal: 1000, discount: 0, total: 1000 }
    )

    Midtrans::Quote.stub(:call, ->(**) { quote }) do
      post signed_path("/api/midtrans/checkout/sessions"),
        params: body_json(rate: { handle: "standard", title: "Standard Shipping", price: 1 }),
        headers: { "CONTENT_TYPE" => "application/json" }
    end

    assert_response :unprocessable_entity
    assert_match(/Shipping rate price changed/, response.body)
  end

  test "sessions reports when the gateway is not configured" do
    quote = Midtrans::Quote::Result.new(
      rates: [ { handle: "standard", title: "Standard Shipping", price: 0, currency: "IDR" } ],
      totals: { currency: "IDR", subtotal: 1000, discount: 0, total: 1000 }
    )

    Midtrans::Quote.stub(:call, ->(**) { quote }) do
      Midtrans::Gateway.stub(:create_session, ->(**) { raise Midtrans::Gateway::NotConfigured, "MIDTRANS_SERVER_KEY is not configured" }) do
        post signed_path("/api/midtrans/checkout/sessions"),
          params: body_json(rate: { handle: "standard", title: "Standard Shipping", price: 0 }),
          headers: { "CONTENT_TYPE" => "application/json" }
      end
    end

    assert_response :service_unavailable
  end

  test "shipping_rates lazily creates the storefront token when missing" do
    shop = shops(:regular_shop)
    shop.update!(storefront_access_token: nil, storefront_access_token_id: nil)
    quote = Midtrans::Quote::Result.new(
      rates: [ { handle: "standard", title: "Standard Shipping", price: 900, currency: "IDR" } ],
      totals: { currency: "IDR", subtotal: 5000, discount: 250, total: 5250 }
    )
    ensured = false

    Shops::StorefrontAccessToken.stub(:ensure!, ->(shop:, session:) {
      ensured = true
      shop.update!(storefront_access_token: "shpat_created")
    }) do
      ShopifyApp::SessionRepository.stub(:retrieve_shop_session_by_shopify_domain, ->(*) { :fake_session }) do
        Midtrans::Quote.stub(:call, ->(**) { quote }) do
          post signed_path("/api/midtrans/checkout/shipping-rates"),
            params: body_json, headers: { "CONTENT_TYPE" => "application/json" }
        end
      end
    end

    assert_response :success
    assert ensured, "expected ensure! to be called"
    assert_equal "shpat_created", shop.reload.storefront_access_token
  end

  test "shipping_rates returns 422 when the storefront token cannot be ensured" do
    shop = shops(:regular_shop)
    shop.update!(storefront_access_token: nil, storefront_access_token_id: nil)

    Shops::StorefrontAccessToken.stub(:ensure!, ->(shop:, session:) { raise ShopifyAPI::Errors::HttpResponseError, "403 Forbidden" }) do
      ShopifyApp::SessionRepository.stub(:retrieve_shop_session_by_shopify_domain, ->(*) { :fake_session }) do
        Midtrans::Quote.stub(:call, ->(**) { raise Midtrans::Quote::StorefrontAccessDenied, "Storefront access token is missing" }) do
          post signed_path("/api/midtrans/checkout/shipping-rates"),
            params: body_json, headers: { "CONTENT_TYPE" => "application/json" }
        end
      end
    end

    assert_response :unprocessable_entity
    assert_match(/Storefront access token is missing/, response.body)
  end

  private

  def signed_path(path, shop: "regular-shop.myshopify.com", secret: ShopifyApp.configuration.secret)
    "#{path}?#{signed_params(shop: shop, secret: secret).to_query}"
  end

  def signed_params(shop: "regular-shop.myshopify.com", secret: ShopifyApp.configuration.secret)
    base = {
      shop: shop,
      path_prefix: "/apps/midtrans",
      timestamp: "1750000000"
    }
    unordered = base.merge(signature: signature_for(base, secret))
    unordered.to_a.sort_by(&:first).to_h
  end

  def signature_for(params, secret = ShopifyApp.configuration.secret)
    sorted = params.sort.map { |key, value| "#{key}=#{Array(value).join(",")}" }.join
    OpenSSL::HMAC.hexdigest("sha256", secret, sorted)
  end

  def body_json(rate: nil)
    payload = {
      cart_token: "abc123",
      customer: { email: "buyer@example.com", first_name: "Ada", last_name: "Lovelace", phone: "" },
      shipping_address: {
        address1: "1 Main St", address2: "", city: "Toronto",
        country: "Canada", province: "ON", zip: "M5V 2T6"
      }
    }
    payload[:shipping_rate] = rate if rate
    payload.to_json
  end
end
