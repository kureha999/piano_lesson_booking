class CreateMakeupReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :makeup_reservations do |t|
      # キャンセルしても行は残す（履歴）。振替権・振替枠・生徒は削除できない（外部キーは削除を制限する）
      t.references :makeup_credit, null: false, foreign_key: true, index: false
      t.references :makeup_slot, null: false, foreign_key: true
      t.references :student, null: false, foreign_key: true
      t.datetime :canceled_at # キャンセルした日時（NULL は、有効な予約）

      t.timestamps

      # 1つの振替権で、有効な予約は1つまで
      t.index :makeup_credit_id, unique: true, where: "canceled_at IS NULL",
        name: "index_makeup_reservations_on_credit_active"
      # 同じ生徒が同じ枠を二重に予約しない
      t.index [ :makeup_slot_id, :student_id ], unique: true, where: "canceled_at IS NULL",
        name: "index_makeup_reservations_on_slot_and_student_active"
    end
  end
end
