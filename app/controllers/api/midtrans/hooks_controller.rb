# frozen_string_literal: true

class Api::Midtrans::HooksController < ApplicationController
  skip_forgery_protection

  # Receives Midtrans HTTP(S) payment notifications after a transaction status
  # change. Verifies the SHA512 signature, correlates the payment back to the
  # pending MidtransCheckout via order_id (== our custom_reference), integrity-
  # checks the gross_amount, applies the status transition, and on capture/
  # settlement enqueues a job that creates the Shopify Order via orderCreate.
  def create
    payload = JSON.parse(request.raw_post)

    unless valid_signature?(payload)
      return render json: { error: "Invalid signature" }, status: :bad_request
    end

    checkout = MidtransCheckout.find_by_order_id(payload["order_id"])
    return render json: { error: "Unknown checkout" }, status: :not_found unless checkout

    unless amount_matches?(payload, checkout)
      return render json: { error: "Amount mismatch" }, status: :conflict
    end

    handle_status(payload, checkout)

    head :ok
  rescue JSON::ParserError
    render json: { error: "Invalid JSON" }, status: :bad_request
  end

  private

  def valid_signature?(payload)
    server_key = ENV["MIDTRANS_SERVER_KEY"]
    return false if server_key.blank?

    order_id = payload["order_id"].to_s
    status_code = payload["status_code"].to_s
    gross_amount = payload["gross_amount"].to_s

    expected = OpenSSL::Digest::SHA512.hexdigest("#{order_id}#{status_code}#{gross_amount}#{server_key}")
    actual = payload["signature_key"].to_s
    ActiveSupport::SecurityUtils.secure_compare(expected, actual)
  end

  def amount_matches?(payload, checkout)
    expected = checkout.total_amount.to_i
    actual = Midtrans::Money.to_minor_units_from_decimal(payload["gross_amount"])
    expected == actual
  end

  def handle_status(payload, checkout)
    status = payload["transaction_status"]

    case status
    when "capture", "settlement"
      checkout.update!(
        midtrans_transaction_id: payload["transaction_id"],
        midtrans_status: status,
        payment_type: payload["payment_type"],
        fraud_status: payload["fraud_status"],
        status: :paid,
        paid_at: payload["settlement_time"].presence || Time.current,
        raw_payload: payload
      )
      MidtransCreateOrderJob.perform_later(checkout.id)
    when "pending", "challenge", "authorize"
      # VA / unsettled: record status for audit but do not mark paid or create
      # the order yet (payment not captured).
      checkout.update!(
        midtrans_status: status,
        payment_type: payload["payment_type"],
        fraud_status: payload["fraud_status"],
        raw_payload: payload
      )
    else
      # deny, cancel, expire, failure, refund, chargeback, partial_refund, etc.
      checkout.update!(
        midtrans_transaction_id: payload["transaction_id"],
        midtrans_status: status,
        payment_type: payload["payment_type"],
        fraud_status: payload["fraud_status"],
        status: :failed,
        raw_payload: payload
      )
    end
  end
end
