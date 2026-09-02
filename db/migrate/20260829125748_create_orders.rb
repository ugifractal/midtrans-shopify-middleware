class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :shop, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :shopify_order_id, null: false
      t.string :name
      t.string :currency, limit: 3
      t.string :financial_status
      t.string :fulfillment_status
      t.decimal :total_price, precision: 10, scale: 2
      t.datetime :placed_at
      t.jsonb :raw_payload
      t.timestamps
    end

    add_index :orders, :shopify_order_id, unique: true
  end
end
