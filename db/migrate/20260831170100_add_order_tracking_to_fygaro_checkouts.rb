# frozen_string_literal: true

class AddOrderTrackingToFygaroCheckouts < ActiveRecord::Migration[8.1]
  def change
    add_column :fygaro_checkouts, :draft_order_id, :string
    add_column :fygaro_checkouts, :fygaro_order_id, :string
    add_column :fygaro_checkouts, :admin_order_created_at, :datetime
  end
end
