# frozen_string_literal: true

require "base64"
require "json"
require "net/http"

module Midtrans
  # Creates a Midtrans Snap transaction and redirects the buyer to the
  # Midtrans-hosted payment page. Snap locks the amount server-side on
  # transaction creation, so the buyer cannot edit it.
  #
  # Configure with MIDTRANS_SERVER_KEY and MIDTRANS_IS_PRODUCTION (true => live
  # app.midtrans.com, anything else => sandbox). MIDTRANS_CLIENT_KEY is optional
  # and only needed if you later switch the frontend to the snap.js popup.
  class Gateway
    class NotConfigured < StandardError; end
    class Error < StandardError; end

    Session = Struct.new(:session_id, :redirect_url, keyword_init: true)

    SANDBOX_URL = "https://app.sandbox.midtrans.com/snap/v1/transactions"
    PRODUCTION_URL = "https://app.midtrans.com/snap/v1/transactions"

    def self.create_session(payload)
      new.create_session(payload)
    end

    def create_session(payload)
      server_key = ENV.fetch("MIDTRANS_SERVER_KEY") do
        raise NotConfigured, "MIDTRANS_SERVER_KEY is not configured"
      end

      uri = URI(transactions_url)
      body = build_body(payload)
      response = post_json(uri, body, server_key)

      token = response["token"]
      redirect_url = response["redirect_url"]
      raise Error, "Midtrans returned no transaction token" if token.blank?

      Session.new(session_id: token, redirect_url: redirect_url)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
      raise Error, "Midtrans request failed: #{e.message}"
    end

    private

    def transactions_url
      ENV.fetch("MIDTRANS_IS_PRODUCTION", "").casecmp?("true") ? PRODUCTION_URL : SANDBOX_URL
    end

    def build_body(payload)
      customer = payload[:customer] || {}
      shipping_address = payload[:shipping_address] || {}

      {
        transaction_details: {
          order_id: payload.fetch(:custom_reference),
          gross_amount: minor_to_decimal(payload.fetch(:total_amount))
        },
        customer_details: {
          first_name: customer[:first_name].to_s.presence,
          last_name: customer[:last_name].to_s.presence,
          email: customer[:email].to_s.presence,
          phone: customer[:phone].to_s.presence
        }.compact,
        item_details: item_details(payload),
        shipping_address: shipping_address_fields(shipping_address),
        credit_card: { secure: true }
      }.compact
    end

    def item_details(payload)
      items = Array(payload[:line_items]).map do |item|
        {
          id: item[:variant_id].to_s.presence,
          name: (item[:product_title] || item[:variant_title]).to_s,
          price: minor_to_decimal(item[:price]),
          quantity: item[:quantity].to_i
        }.compact
      end

      discount = payload.dig(:totals, :discount).to_i
      shipping = payload.dig(:totals, :shipping).to_i
      items << { name: "Discount", price: -minor_to_decimal(discount), quantity: 1 } if discount.positive?
      items << { name: "Shipping", price: minor_to_decimal(shipping), quantity: 1 } if shipping.positive?

      item_sum = items.sum { |item| item[:price].to_f * item[:quantity].to_i }
      gross_amount = minor_to_decimal(payload.fetch(:total_amount)).to_f
      return items if (item_sum - gross_amount).abs < 0.01

      raise Error, "Midtrans item_details sum (%.2f) does not equal gross_amount (%.2f)" % [ item_sum, gross_amount ]
    end

    def shipping_address_fields(address)
      {
        first_name: address[:first_name].to_s.presence,
        last_name: address[:last_name].to_s.presence,
        email: address[:email].to_s.presence,
        address: address[:address1].to_s.presence,
        city: address[:city].to_s.presence,
        postal_code: address[:zip].to_s.presence,
        country_code: normalize_country(address[:country]),
        phone: address[:phone].to_s.presence
      }.compact.presence
    end

    def normalize_country(country)
      raw = country.to_s.upcase.delete("^A-Z")
      raw if raw.match?(/\A[A-Z]{2}\z/)
    end

    def minor_to_decimal(minor_units)
      (minor_units.to_i / 100.0).round(2) if minor_units
    end

    def post_json(uri, body, server_key)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri)
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Basic #{Base64.strict_encode64("#{server_key}:")}"
      request.body = JSON.generate(body)

      response = http.request(request)
      data = parse_response(response)
      raise Error, "Midtrans error #{response.code}: #{data["error_message"] || response.body}" unless response.is_a?(Net::HTTPSuccess)

      data
    end

    def parse_response(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      {}
    end
  end
end
