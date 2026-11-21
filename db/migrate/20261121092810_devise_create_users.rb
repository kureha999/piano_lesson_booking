# frozen_string_literal: true

class DeviseCreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      ## Database authenticatable
      t.string :email,              null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      ## アプリ独自の列
      t.string  :name, null: false                 # 表示名
      t.integer :role, null: false, default: 0     # 0：保護者、1：先生

      ## Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Rememberable
      t.datetime :remember_created_at

      t.timestamps null: false
    end

    add_index :users, :email,                unique: true
    add_index :users, :reset_password_token, unique: true
    # 先生（role = 1）は教室に1人だけ。同時に2人作ろうとしても DB が止める
    add_index :users, :role, unique: true, where: "role = 1", name: "index_users_on_role_teacher_only"
  end
end
