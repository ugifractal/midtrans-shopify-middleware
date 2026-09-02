class AddStorefrontAccessTokenToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :storefront_access_token, :string
    add_column :shops, :storefront_access_token_id, :bigint
  end
end
