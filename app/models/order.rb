# frozen_string_literal: true

class Order < ApplicationRecord
  belongs_to :shop

  validates :shopify_order_id, presence: true, uniqueness: true
end
