class AddShopAccessScopesColumn < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :access_scopes, :string, default: "", null: false
  end
end
