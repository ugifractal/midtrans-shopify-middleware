# frozen_string_literal: true

class Shop < ActiveRecord::Base
  include ShopifyApp::ShopSessionStorage

  has_many :orders, dependent: :destroy
  has_many :midtrans_checkouts, dependent: :destroy

  def api_version
    ShopifyApp.configuration.api_version
  end
end
