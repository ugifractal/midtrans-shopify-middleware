class CreateFygaroCheckouts < ActiveRecord::Migration[8.1]
  def change
    create_table :fygaro_checkouts do |t|
      t.references :shop, null: false, foreign_key: { on_delete: :cascade }
      t.string :custom_reference, null: false
      t.string :cart_token, null: false
      t.string :session_id
      t.jsonb :customer
      t.jsonb :shipping_address
      t.jsonb :shipping_rate
      t.jsonb :totals
      t.jsonb :line_items
      t.bigint :total_amount
      t.string :fygaro_amount
      t.string :currency, limit: 10
      t.integer :status, default: 0, null: false
      t.string :fygaro_transaction_id
      t.datetime :paid_at
      t.jsonb :raw_payload
      t.timestamps
    end

    add_index :fygaro_checkouts, :custom_reference, unique: true
    add_index :fygaro_checkouts, :fygaro_transaction_id, unique: true
  end
end
