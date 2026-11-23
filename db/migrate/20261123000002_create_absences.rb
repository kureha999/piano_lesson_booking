class CreateAbsences < ActiveRecord::Migration[8.1]
  def change
    create_table :absences do |t|
      # 履歴なので、固定枠・連絡した人は削除できない（外部キーは削除を制限する）
      t.references :lesson_slot, null: false, foreign_key: true
      t.date :lesson_on, null: false                                          # 欠席するレッスンの日付
      t.references :reported_by, null: false, foreign_key: { to_table: :users } # 連絡した人
      t.integer :no_credit_reason                                             # NULL：振替権あり、0：欠席連絡の締切後、1：月の上限を超えた

      t.timestamps # created_at が、連絡した日時

      # 同じレッスンの欠席を二重に登録しない
      t.index [ :lesson_slot_id, :lesson_on ], unique: true
    end
  end
end
