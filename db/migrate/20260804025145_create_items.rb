class CreateItems < ActiveRecord::Migration[8.1]
  def change
    create_table :items do |t|
      t.references :channel, null: false, foreign_key: true
      t.string :kind, null: false
      t.text :body
      t.datetime :expires_at

      t.timestamps
    end

    add_index :items, :expires_at
    # Channel timeline: filter by channel_id, order by created_at
    add_index :items, [ :channel_id, :created_at ]
  end
end
