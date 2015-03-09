class CreateShopProducts < ActiveRecord::Migration
  def change
    create_table :shop_products do |t|
      t.string :name
      t.references :account, index: true
      t.string :code
      t.references :category, index: true
      t.integer :price
      t.integer :discount
      t.boolean :is_material
      t.integer :transport_fee
      t.integer :quantity
      t.text :description
      t.references :picture, index: true
      t.integer :view_count
      t.integer :the_order
      t.integer :tag_order      
      t.boolean :is_recommend
      t.boolean :is_enabled      

      t.timestamps
    end
  end
end
