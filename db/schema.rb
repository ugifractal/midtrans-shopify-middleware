# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_01_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "midtrans_checkouts", force: :cascade do |t|
    t.datetime "admin_order_created_at"
    t.string "cart_token", null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 10
    t.string "custom_reference", null: false
    t.jsonb "customer"
    t.string "draft_order_id"
    t.string "fraud_status"
    t.jsonb "line_items"
    t.string "midtrans_amount"
    t.string "midtrans_order_id"
    t.string "midtrans_status"
    t.string "midtrans_transaction_id"
    t.datetime "paid_at"
    t.string "payment_type"
    t.jsonb "raw_payload"
    t.string "session_id"
    t.jsonb "shipping_address"
    t.jsonb "shipping_rate"
    t.bigint "shop_id", null: false
    t.integer "status", default: 0, null: false
    t.bigint "total_amount"
    t.jsonb "totals"
    t.datetime "updated_at", null: false
    t.index ["custom_reference"], name: "index_midtrans_checkouts_on_custom_reference", unique: true
    t.index ["midtrans_transaction_id"], name: "index_midtrans_checkouts_on_midtrans_transaction_id", unique: true
    t.index ["shop_id"], name: "index_midtrans_checkouts_on_shop_id"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", limit: 3
    t.string "financial_status"
    t.string "fulfillment_status"
    t.string "name"
    t.datetime "placed_at"
    t.jsonb "raw_payload"
    t.bigint "shop_id", null: false
    t.bigint "shopify_order_id", null: false
    t.decimal "total_price", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.index ["shop_id"], name: "index_orders_on_shop_id"
    t.index ["shopify_order_id"], name: "index_orders_on_shopify_order_id", unique: true
  end

  create_table "shops", force: :cascade do |t|
    t.string "access_scopes", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "refresh_token"
    t.datetime "refresh_token_expires_at"
    t.string "shopify_domain", null: false
    t.string "shopify_token", null: false
    t.string "storefront_access_token"
    t.bigint "storefront_access_token_id"
    t.datetime "updated_at", null: false
    t.index ["shopify_domain"], name: "index_shops_on_shopify_domain", unique: true
  end

  add_foreign_key "midtrans_checkouts", "shops", on_delete: :cascade
  add_foreign_key "orders", "shops", on_delete: :cascade
end
