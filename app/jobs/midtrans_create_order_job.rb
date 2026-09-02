# frozen_string_literal: true

class MidtransCreateOrderJob < ApplicationJob
  queue_as :default

  retry_on Midtrans::OrderCreator::AdminAccessError, wait: 10.seconds, attempts: 5

  def perform(checkout_id)
    checkout = MidtransCheckout.find_by(id: checkout_id)
    return if checkout.nil?
    return unless checkout.paid?

    Midtrans::OrderCreator.call(checkout: checkout)
  rescue Midtrans::OrderCreator::AlreadyCreated
    nil
  end
end
