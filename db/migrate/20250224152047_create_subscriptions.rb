class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      t.references :subscribable, polymorphic: true, null: false, index: true
      t.references :user, null: false, foreign_key: true

      t.timestamps

      t.index [ :subscribable_type, :subscribable_id, :user_id ], unique: true
    end
  end
end
