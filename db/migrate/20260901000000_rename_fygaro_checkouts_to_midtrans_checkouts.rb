class RenameFygaroCheckoutsToMidtransCheckouts < ActiveRecord::Migration[8.1]
  def change
    rename_table :fygaro_checkouts, :midtrans_checkouts

    rename_column :midtrans_checkouts, :fygaro_amount, :midtrans_amount
    rename_column :midtrans_checkouts, :fygaro_order_id, :midtrans_order_id
    rename_column :midtrans_checkouts, :fygaro_transaction_id, :midtrans_transaction_id
    # NOTE: Postgres auto-renames the table's indexes (including the
    # fygaro_transaction_id unique index) when rename_table is called above, so
    # no explicit rename_index is needed.

    change_column :midtrans_checkouts, :status, :integer, default: 0, null: false

    add_column :midtrans_checkouts, :midtrans_status, :string
    add_column :midtrans_checkouts, :payment_type, :string
    add_column :midtrans_checkouts, :fraud_status, :string
  end
end
