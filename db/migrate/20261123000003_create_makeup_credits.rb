class CreateMakeupCredits < ActiveRecord::Migration[8.1]
  def change
    create_table :makeup_credits do |t|
      # 生徒を持つのは、同じ生徒が同じ枠を二重に予約しないことを DB の制約で守るため（README 12-6）
      t.references :student, null: false, foreign_key: true
      # 欠席1回に振替権は1つまで（一意インデックス）
      t.references :absence, null: false, foreign_key: true, index: { unique: true }
      t.date :expires_on, null: false # 受講できる最終日

      t.timestamps
    end
  end
end
