# frozen_string_literal: true

require "test_helper"

class Midtrans::GatewayTest < ActiveSupport::TestCase
  setup do
    @payload = {
      custom_reference: "a1b2c3d4e5f6a7b8c9d0",
      total_amount: 1_164_580, # 11645.80 IDR
      customer: { first_name: "Budi", last_name: "Pratama", email: "buyer@example.com" },
      shipping_address: { address1: "Jl. Sudirman 1", city: "Jakarta", zip: "10220", country: "ID" },
      shipping_rate: { handle: "standard", title: "Standard", price: 10_000 },
      totals: { currency: "IDR", subtotal: 1_224_580, discount: 70_000, total: 1_154_580, shipping: 10_000 },
      line_items: [
        { variant_id: "gid://shopify/ProductVariant/1", variant_title: "Widget", price: 300_000, quantity: 3 },
        { variant_id: "gid://shopify/ProductVariant/2", variant_title: "Gadget", price: 162_290, quantity: 2 }
      ]
    }
  end

  test "builds item_details that sum to gross_amount including discount and shipping" do
    body = build_body(@payload)

    item_sum = body[:item_details].sum { |item| item[:price].to_f * item[:quantity].to_i }
    assert_in_delta body.dig(:transaction_details, :gross_amount), item_sum, 0.01
  end

  test "includes a negative discount item when a discount is present" do
    body = build_body(@payload)

    discount_item = body[:item_details].find { |item| item[:name] == "Discount" }
    assert_not_nil discount_item
    assert_equal(-700.00, discount_item[:price])
    assert_equal 1, discount_item[:quantity]
  end

  test "includes a shipping item when shipping is present" do
    body = build_body(@payload)

    shipping_item = body[:item_details].find { |item| item[:name] == "Shipping" }
    assert_not_nil shipping_item
    assert_equal 100.00, shipping_item[:price]
    assert_equal 1, shipping_item[:quantity]
  end

  test "omits discount and shipping items when they are zero" do
    payload = @payload.deep_merge(totals: { discount: 0, shipping: 0 }, total_amount: 1_224_580)
    body = build_body(payload)

    names = body[:item_details].map { |item| item[:name] }
    assert_not_includes names, "Discount"
    assert_not_includes names, "Shipping"
  end

  test "uses numeric (Float) prices" do
    body = build_body(@payload)

    assert body[:item_details].all? { |item| item[:price].is_a?(Float) }
    assert body.dig(:transaction_details, :gross_amount).is_a?(Float)
  end

  test "raises Error when item_details do not reconcile with gross_amount" do
    payload = @payload.merge(total_amount: 999_999) # mismatch

    error = assert_raises(Midtrans::Gateway::Error) do
      build_body(payload)
    end
    assert_match(/does not equal gross_amount/, error.message)
  end

  test "no discount and no shipping produces a matching plain item sum" do
    payload = {
      custom_reference: "ref",
      total_amount: 20_000, # subtotal only, no discount, no shipping
      totals: { currency: "IDR", subtotal: 20_000, discount: 0, total: 20_000, shipping: 0 },
      line_items: [ { variant_id: "gid://shopify/ProductVariant/3", variant_title: "Simple", price: 10_000, quantity: 2 } ]
    }
    body = build_body(payload)

    names = body[:item_details].map { |item| item[:name] }
    assert_equal [ "Simple" ], names
    item_sum = body[:item_details].sum { |item| item[:price].to_f * item[:quantity].to_i }
    assert_in_delta 200.00, item_sum, 0.01
  end

  private

  def build_body(payload)
    captured = nil
    gateway = Midtrans::Gateway.new
    gateway.stub(:post_json, ->(uri, body, server_key) {
      captured = [ uri, body, server_key ]
      { "token" => "snap-token", "redirect_url" => "https://app.sandbox.midtrans.com/snap/v2/vtweb/x" }
    }) do
      ENV["MIDTRANS_SERVER_KEY"] = "test-server-key"
      gateway.create_session(payload)
    end
    captured[1]
  ensure
    ENV["MIDTRANS_SERVER_KEY"] = nil
  end
end
