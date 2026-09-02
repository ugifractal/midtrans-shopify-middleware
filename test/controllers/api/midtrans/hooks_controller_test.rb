# frozen_string_literal: true

require "test_helper"

class Api::Midtrans::HooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @server_key = "test-midtrans-server-key"
    ENV["MIDTRANS_SERVER_KEY"] = @server_key

    @shop = shops(:regular_shop)
    @total_amount = 1_009_000 # 10090.00 IDR minor units
    @checkout = MidtransCheckout.create!(
      shop: @shop,
      custom_reference: "a1b2c3d4e5f6a7b8c9d0",
      cart_token: "hWNGEGcVbnphZlhxyjGI1ym7V?key=430bcfc77927fa3d39ced69844a74ce0",
      status: :pending,
      customer: { email: "buyer@example.com", first_name: "Budi", last_name: "Pratama" },
      shipping_address: { address1: "Jl. Sudirman", city: "Jakarta", country: "Indonesia" },
      totals: { currency: "IDR", subtotal: 1_000_000, discount: 0, total: 1_000_000, shipping: 9_000 },
      line_items: [ { product_title: "Widget", quantity: 1, price: 1_000_000 } ],
      total_amount: @total_amount,
      currency: "IDR"
    )
  end

  test "marks a pending checkout paid and enqueues order creation on capture" do
    assert_enqueued_with(job: MidtransCreateOrderJob, args: [ @checkout.id ]) do
      post_hooked(notification(status: "capture"))
    end

    assert_response :success
    @checkout.reload
    assert @checkout.paid?
    assert_equal "08d7360a-fc4b-46ad-a513-0a3d3fd3771c", @checkout.midtrans_transaction_id
    assert_equal "capture", @checkout.midtrans_status
    assert_equal "credit_card", @checkout.payment_type
    assert_not_nil @checkout.paid_at
  end

  test "marks a checkout paid on settlement" do
    assert_enqueued_with(job: MidtransCreateOrderJob, args: [ @checkout.id ]) do
      post_hooked(notification(status: "settlement", payment_type: "gopay"))
    end

    assert_response :success
    @checkout.reload
    assert @checkout.paid?
    assert_equal "gopay", @checkout.payment_type
  end

  test "records pending statuses without creating an order" do
    assert_no_enqueued_jobs(only: MidtransCreateOrderJob) do
      post_hooked(notification(status: "pending", payment_type: "bank_transfer"))
    end

    assert_response :success
    @checkout.reload
    assert @checkout.pending?, "checkout should remain pending"
    assert_equal "pending", @checkout.midtrans_status
    assert_nil @checkout.midtrans_transaction_id
  end

  test "marks a checkout failed on deny" do
    assert_no_enqueued_jobs(only: MidtransCreateOrderJob) do
      post_hooked(notification(status: "deny"))
    end

    assert_response :success
    @checkout.reload
    assert @checkout.failed?
    assert_equal "deny", @checkout.midtrans_status
  end

  test "rejects a notification whose gross_amount does not match the snapshot" do
    # Signature is valid for this exact body, but the amount differs from the
    # stored total_amount (1_009_000 minor units == "10090.00").
    tampered = notification(status: "capture", gross_amount: "100.00")
    post_hooked(tampered)

    assert_response :conflict
    assert @checkout.reload.pending?, "checkout should remain pending"
  end

  test "rejects a notification with an invalid signature" do
    bad = notification(status: "capture").merge("signature_key" => "deadbeef")
    post_hooked(bad)

    assert_response :bad_request
    assert @checkout.reload.pending?
  end

  test "rejects a notification for an unknown checkout" do
    unknown = notification(status: "capture", order_id: "unknown-ref")
    post_hooked(unknown)

    assert_response :not_found
  end

  test "is idempotent for a repeated transaction id" do
    2.times { post_hooked(notification(status: "capture")) }

    assert_response :success
    @checkout.reload
    assert @checkout.paid?
  end

  test "rejects invalid JSON" do
    post "/api/midtrans/hooks", params: "not json{", headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :bad_request
  end

  private

  def notification(status:, payment_type: "credit_card", order_id: "a1b2c3d4e5f6a7b8c9d0", gross_amount: "10090.00", status_code: "200")
    {
      "transaction_time" => "2026-09-01 10:00:00",
      "transaction_status" => status,
      "transaction_id" => "08d7360a-fc4b-46ad-a513-0a3d3fd3771c",
      "status_message" => "midtrans payment notification",
      "status_code" => status_code,
      "payment_type" => payment_type,
      "order_id" => order_id,
      "merchant_id" => "G123456",
      "gross_amount" => gross_amount,
      "fraud_status" => "accept",
      "currency" => "IDR",
      "signature_key" => signature_key(order_id, status_code, gross_amount)
    }
  end

  def signature_key(order_id, status_code, gross_amount)
    OpenSSL::Digest::SHA512.hexdigest("#{order_id}#{status_code}#{gross_amount}#{@server_key}")
  end

  def post_hooked(body)
    post "/api/midtrans/hooks", params: body.to_json, headers: { "CONTENT_TYPE" => "application/json" }
  end
end
