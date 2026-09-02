# frozen_string_literal: true

require "test_helper"

class Midtrans::OrderCreatorTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
    @shop.update!(shopify_token: "token")
    @checkout = MidtransCheckout.create!(
      shop: @shop,
      custom_reference: "z1z2z3z4z5z6z7z8z9z0",
      cart_token: "raw-cart-token",
      status: :paid,
      midtrans_transaction_id: "txn-123",
      customer: { email: "buyer@example.com", first_name: "Ada", last_name: "Lovelace" },
      shipping_address: { address1: "1 Main St", city: "Toronto", country: "CA", province: "ON", zip: "M5V" },
      shipping_rate: { title: "Standard", price: 900 },
      line_items: [ { variant_id: "gid://shopify/ProductVariant/1", quantity: 2 } ],
      totals: { currency: "IDR", subtotal: 100000, discount: 0, total: 100000, shipping: 900 },
      total_amount: 100900,
      currency: "IDR"
    )
  end

  test "creates the order and records the order id on the checkout" do
    client = fake_client(
      "data" => {
        "orderCreate" => {
          "order" => { "id" => "gid://shopify/Order/42", "name" => "#1001" },
          "userErrors" => []
        }
      }
    )

    order_id = Midtrans::OrderCreator.call(checkout: @checkout, client: client)
    assert_equal "gid://shopify/Order/42", order_id

    @checkout.reload
    assert_equal "gid://shopify/Order/42", @checkout.midtrans_order_id
    assert_not_nil @checkout.admin_order_created_at
  end

  test "sends an orderCreate mutation with the checkout snapshot" do
    captured = nil
    client = fake_client(
      "data" => { "orderCreate" => { "order" => { "id" => "gid://shopify/Order/7" }, "userErrors" => [] } }
    ) { |query, variables| captured = [ query, variables ] }

    Midtrans::OrderCreator.call(checkout: @checkout, client: client)

    query, variables = captured
    assert_includes query, "orderCreate"
    order = variables.fetch(:order)
    assert_equal [ { variantId: "gid://shopify/ProductVariant/1", quantity: 2 } ], order[:lineItems]
    assert_equal "Standard", order.dig(:shippingLines, 0, :title)
    assert_equal "9.00", order.dig(:shippingLines, 0, :priceSet, :shopMoney, :amount)
    assert_equal "IDR", order.dig(:shippingLines, 0, :priceSet, :shopMoney, :currencyCode)
    assert_equal "CA", order.dig(:shippingAddress, :countryCode)
    assert_equal({ email: "buyer@example.com", firstName: "Ada", lastName: "Lovelace" }, order.dig(:customer, :toUpsert))
    assert_equal [ "midtrans", "z1z2z3z4z5z6z7z8z9z0" ], order[:tags]
    assert_equal "PAID", order[:financialStatus]
    assert_equal "midtrans", order.dig(:transactions, 0, :gateway)
    assert_equal "SALE", order.dig(:transactions, 0, :kind)
    assert_equal "SUCCESS", order.dig(:transactions, 0, :status)
    assert_equal "1009.00", order.dig(:transactions, 0, :amountSet, :shopMoney, :amount)
    assert_equal "IDR", order.dig(:transactions, 0, :amountSet, :shopMoney, :currencyCode)
  end

  test "raises AlreadyCreated when the checkout already has an order id" do
    @checkout.update!(midtrans_order_id: "gid://shopify/Order/99")

    assert_raises(Midtrans::OrderCreator::AlreadyCreated) do
      Midtrans::OrderCreator.call(checkout: @checkout, client: fake_client({}))
    end
  end

  test "raises AdminAccessError on userErrors" do
    client = fake_client(
      "data" => { "orderCreate" => { "order" => nil, "userErrors" => [ { "field" => "payment", "message" => "nope" } ] } }
    )

    assert_raises(Midtrans::OrderCreator::AdminAccessError) do
      Midtrans::OrderCreator.call(checkout: @checkout, client: client)
    end
  end

  test "raises AdminAccessError when no Shopify session exists" do
    ShopifyApp::SessionRepository.stub(:retrieve_shop_session_by_shopify_domain, ->(*) { nil }) do
      assert_raises(Midtrans::OrderCreator::AdminAccessError) do
        Midtrans::OrderCreator.call(checkout: @checkout)
      end
    end
  end

  private

  def fake_client(body, &block)
    Struct.new(:body, :capture) do
      def query(query:, variables: nil, response_as_struct: false)
        capture&.call(query, variables)
        Struct.new(:body).new(body)
      end

      def respond_to_missing?(*)
        true
      end
    end.new(body, block)
  end
end
