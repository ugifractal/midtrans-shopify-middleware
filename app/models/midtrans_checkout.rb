# frozen_string_literal: true

class MidtransCheckout < ApplicationRecord
  belongs_to :shop

  enum :status, { pending: 0, paid: 1, failed: 2 }

  validates :custom_reference, presence: true, uniqueness: true
  validates :cart_token, presence: true

  scope :pending, -> { where(status: :pending) }

  # Converts a Midtrans order_id (== our custom_reference) back to the matching
  # checkout record.
  def self.find_by_order_id(order_id)
    find_by(custom_reference: order_id)
  end
end
