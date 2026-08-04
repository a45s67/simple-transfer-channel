class CreateChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :channels do |t|
      t.string :name, null: false
      t.string :password_digest, null: false

      t.timestamps
    end

    add_index :channels, :name, unique: true
  end
end
