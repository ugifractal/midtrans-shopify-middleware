# frozen_string_literal: true

module Midtrans
  # Creates the Shopify Order for a paid MidtransCheckout directly via the Admin
  # GraphQL API (orderCreate). Runs after the Midtrans payment notification
  # verifies and marks the checkout paid.
  #
  # The order is created in the shop's native currency (IDR) from the snapshot
  # taken at checkout time — the line-item variants, shipping line, and customer.
  # Because the buyer already paid Midtrans off-platform, we record a custom
  # payment (type CUSTOM, gateway "midtrans") referencing the Midtrans
  # transaction id so the resulting order is marked paid with a clear audit trail.
  #
  # Idempotent: if the checkout already has an order id on file we do not create
  # a second order.
  class OrderCreator
    class AdminAccessError < StandardError; end
    class AlreadyCreated < StandardError; end

    CREATE_ORDER = <<~GRAPHQL
      mutation MidtransCreateOrder($order: OrderCreateOrderInput!) {
        orderCreate(order: $order) {
          order {
            id
            name
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    def self.call(checkout:, client: nil)
      new(checkout, client: client).call
    end

    def initialize(checkout, client: nil)
      @checkout = checkout
      @client = client
    end

    def call
      raise AlreadyCreated, "Order already created for #{@checkout.custom_reference}" if @checkout.midtrans_order_id.present?

      body = admin_client.query(query: CREATE_ORDER, variables: { order: order_input }, response_as_struct: false).body
      data = body.dig("data", "orderCreate")
      puts body
      raise AdminAccessError, user_error_message(data) if data.nil? || Array(data["userErrors"]).any?

      order_id = data.dig("order", "id")
      raise AdminAccessError, "orderCreate returned no order for #{@checkout.custom_reference}" if order_id.blank?

      @checkout.update!(midtrans_order_id: order_id, admin_order_created_at: Time.current)
      order_id
    end

    private

    # Injected for tests; production builds a live Admin GraphQL client scoped
    # to the store's session.
    def admin_client
      @client || build_admin_client
    end

    def build_admin_client
      session = ShopifyApp::SessionRepository.retrieve_shop_session_by_shopify_domain(@checkout.shop.shopify_domain)
      raise AdminAccessError, "No Shopify session for #{@checkout.shop.shopify_domain}" if session.nil?

      ShopifyAPI::Clients::Graphql::Admin.new(session: session, api_version: @checkout.shop.api_version)
    end

    def order_input
      {
        email: customer["email"],
        customer: customer_input,
        shippingAddress: shipping_address,
        shippingLines: shipping_lines,
        lineItems: line_items,
        tags: tags,
        customAttributes: custom_attributes,
        transactions: transactions,
        financialStatus: financial_status
      }.compact
    end

    def customer
      @checkout.customer || {}
    end

    # Associate a new (or existing) customer with the order via toUpsert, which is
    # the only way orderCreate accepts customer details in the current API.
    # Blank values (nil or "") are omitted so Shopify doesn't reject an empty
    # phone or a bare whitespace name.
    def customer_input
      attrs = {
        email: present(customer["email"]),
        firstName: present(customer["first_name"]),
        lastName: present(customer["last_name"]),
        phone: present(customer["phone"])
      }.compact
      { toUpsert: attrs } if attrs.any?
    end

    def tags
      [ "midtrans", @checkout.custom_reference.to_s ]
    end

    # Embed the Midtrans transaction id so it survives the round-trip into the
    # created order's custom attributes (readable in the Shopify admin).
    def custom_attributes
      [
        { key: "midtrans_transaction_id", value: @checkout.midtrans_transaction_id.to_s },
        { key: "midtrans_reference", value: @checkout.custom_reference.to_s }
      ]
    end

    def shipping_address
      address = @checkout.shipping_address || {}
      {
        address1: value(address, :address1),
        address2: value(address, :address2),
        city: value(address, :city),
        countryCode: value(address, :country).to_s.upcase.presence,
        provinceCode: value(address, :province),
        zip: value(address, :zip)
      }.compact
    end

    def shipping_lines
      rate = @checkout.shipping_rate || {}
      return if rate.blank?

      [ {
        title: value(rate, :title).presence || "Shipping",
        code: value(rate, :handle).to_s.presence,
        priceSet: {
          shopMoney: {
            amount: minor_to_decimal(value(rate, :price)),
            currencyCode: @checkout.currency
          }
        }
      }.compact ]
    end

    def line_items
      (@checkout.line_items || []).map do |item|
        {
          variantId: value(item, :variant_id),
          quantity: value(item, :quantity)
        }.compact
      end
    end

    # Record the off-platform Midtrans tender as a SALE transaction with SUCCESS
    # status so the order is created as paid, embedding the Midtrans transaction
    # id in the receipt and order attributes for reconciliation.
    def transactions
      [ {
        amountSet: {
          shopMoney: {
            amount: minor_to_decimal(@checkout.total_amount),
            currencyCode: @checkout.currency
          }
        },
        gateway: "midtrans",
        kind: "SALE",
        status: "SUCCESS",
        test: false,
        receiptJson: {
          midtrans_transaction_id: @checkout.midtrans_transaction_id.to_s,
          midtrans_reference: @checkout.custom_reference.to_s
        }
      }.compact ]
    end

    def financial_status
      "PAID"
    end

    def minor_to_decimal(minor_units)
      format("%.2f", minor_units.to_f / 100) if minor_units
    end

    def value(hash, key)
      hash[key.to_s] || hash[key]
    end

    def present(value)
      return if value.blank?

      value
    end

    def user_error_message(data)
      errors = Array(data["userErrors"]).map { |e| [ e["field"], e["message"] ].compact.join(": ") }
      errors.empty? ? "Unknown Shopify GraphQL error" : errors.join("; ")
    end
  end
end
