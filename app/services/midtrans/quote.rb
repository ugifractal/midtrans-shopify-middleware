# frozen_string_literal: true

module Midtrans
  # Quotes shipping options and authoritative cart totals for a Storefront Cart
  # using Shopify's own calculations (discounts, taxes, duties, delivery).
  #
  # Adds a one-time-use delivery address onto the cart via cartDeliveryAddressesAdd
  # so Shopify computes the delivery groups; amounts are returned as minor units.
  class Quote
    Result = Struct.new(:rates, :totals, :line_items, keyword_init: true)

    class CartNotFoundError < StandardError; end
    class StorefrontAccessDenied < StandardError; end
    class InvalidCountryError < StandardError; end

    MUTATION = <<~GRAPHQL
      mutation CartQuote($cartId: ID!, $addresses: [CartSelectableAddressInput!]!) {
        cartDeliveryAddressesAdd(cartId: $cartId, addresses: $addresses) {
          cart {
            id
            cost {
              subtotalAmount { amount currencyCode }
              totalAmount { amount currencyCode }
            }
            discountAllocations {
              discountedAmount { amount currencyCode }
            }
            deliveryGroups(first: 10) {
              edges {
                node {
                  deliveryOptions {
                    handle
                    title
                    estimatedCost { amount currencyCode }
                  }
                }
              }
            }
            lines(first: 250) {
              edges {
                node {
                  id
                  quantity
                  merchandise {
                    ... on ProductVariant {
                      id
                      title
                      sku
                      price { amount currencyCode }
                    }
                  }
                  cost {
                    amountPerQuantity { amount currencyCode }
                    totalAmount { amount currencyCode }
                    subtotalAmount { amount currencyCode }
                    compareAtAmountPerQuantity { amount currencyCode }
                  }
                  discountAllocations {
                    discountedAmount { amount currencyCode }
                  }
                }
              }
            }
          }
          userErrors {
            field
            message
          }
        }
      }
    GRAPHQL

    def self.call(shop:, cart_token:, shipping_address:)
      new(shop: shop, cart_token: cart_token, shipping_address: shipping_address).call
    end

    def initialize(shop:, cart_token:, shipping_address:)
      @shop = shop
      @cart_token = cart_token
      @shipping_address = shipping_address
    end

    def call
      raise StorefrontAccessDenied, "Storefront access token is missing" if @shop.storefront_access_token.blank?

      client = storefront_client

      delivery_address = {
        address: { deliveryAddress: delivery_address_input(country_code) },
        selected: true,
        oneTimeUse: true
      }

      variables = { cartId: cart_gid, addresses: [ delivery_address ] }
      body = client.query(query: MUTATION, variables: variables, response_as_struct: false).body
      data = body.dig("data", "cartDeliveryAddressesAdd")

      errors = Array(data["userErrors"])
      raise CartNotFoundError, errors.first["message"] if data["cart"].nil?

      raise CartNotFoundError, errors.first["message"] if errors.any?

      Result.new(rates: rates(data["cart"]), totals: totals(data["cart"]), line_items: line_items(data["cart"]))
    end

    private

    def cart_gid
      token = @cart_token.to_s
      if token.start_with?("gid://")
        token
      else
        "gid://shopify/Cart/#{token}"
      end
    end

    def storefront_client
      ShopifyAPI::Clients::Graphql::Storefront.new(
        @shop.shopify_domain,
        public_token: @shop.storefront_access_token,
        api_version: @shop.api_version
      )
    end

    def country_code
      raw = @shipping_address[:country].to_s
      code = raw.upcase.delete("^A-Z")
      return code if code.match?(/\A[A-Z]{2}\z/)

      raise InvalidCountryError, "Unsupported country: #{raw.inspect}"
    end

    def delivery_address_input(country_code)
      address = @shipping_address.slice(:address1, :address2, :city, :zip)
      address[:provinceCode] = @shipping_address[:province]
      address.merge(countryCode: country_code).compact
    end

    def rates(cart)
      options = Array(cart.dig("deliveryGroups", "edges")).flat_map { |edge| edge.dig("node", "deliveryOptions") }

      options.map do |option|
        cost = option["estimatedCost"] || {}
        amount = cost["amount"]
        {
          handle: option["handle"],
          title: option["title"],
          price: Midtrans::Money.to_minor_units(amount, cost["currencyCode"]),
          currency: cost["currencyCode"]
        }
      end
    end

    def totals(cart)
      cost = cart["cost"] || {}
      currency = cost.dig("subtotalAmount", "currencyCode")
      discount = cart_discount(cart)

      {
        currency: currency,
        subtotal: Midtrans::Money.to_minor_units(cost.dig("subtotalAmount", "amount"), currency),
        discount: discount,
        total: Midtrans::Money.to_minor_units(cost.dig("totalAmount", "amount"), currency)
      }
    end

    def line_items(cart)
      lines = Array(cart.dig("lines", "edges")).map { |edge| edge["node"] }
      currency = cart.dig("cost", "subtotalAmount", "currencyCode")

      lines.map do |line|
        merchandise = line["merchandise"] || {}
        {
          line_id: line["id"],
          quantity: line["quantity"],
          variant_id: merchandise["id"],
          variant_title: merchandise["title"],
          sku: merchandise["sku"],
          price: Midtrans::Money.to_minor_units(merchandise.dig("price", "amount"), currency),
          total: Midtrans::Money.to_minor_units(line.dig("cost", "totalAmount", "amount"), currency)
        }
      end
    end

    def cart_discount(cart)
      allocations = Array(cart["discountAllocations"])
      line_allocations = Array(cart.dig("lines", "edges")).flat_map do |edge|
        Array(edge.dig("node", "discountAllocations"))
      end
      currency = cart.dig("cost", "subtotalAmount", "currencyCode")

      (allocations + line_allocations).sum do |allocation|
        amount = allocation.dig("discountedAmount", "amount")
        amount_currency = allocation.dig("discountedAmount", "currencyCode") || currency
        Midtrans::Money.to_minor_units(amount, amount_currency)
      end
    end
  end
end
