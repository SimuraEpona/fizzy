class AddStartedOnToCards < ActiveRecord::Migration[8.2]
  def change
    add_column :cards, :started_on, :date
    add_index :cards, :started_on
    add_index :cards, [ :started_on, :due_on ]
  end
end
