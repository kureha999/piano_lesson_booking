class CreateLessonSlots < ActiveRecord::Migration[8.1]
  def change
    create_table :lesson_slots do |t|
      # 生徒に属する。履歴（欠席）が指すので、生徒・枠は削除できない（外部キーは削除を制限する）
      t.references :student, null: false, foreign_key: true
      t.integer :wday, null: false     # 曜日 0:日〜6:土
      t.time :start_time, null: false  # 開始時刻（日本時間の時刻。time 型はタイムゾーンを変換しない）
      t.time :end_time, null: false    # 終了時刻
      t.date :starts_on, null: false   # 適用開始日
      t.date :ends_on                  # 適用終了日（NULL は、終わりなし）

      t.timestamps

      t.check_constraint "wday BETWEEN 0 AND 6", name: "lesson_slots_wday_range"
      t.check_constraint "end_time > start_time", name: "lesson_slots_end_after_start"
      t.check_constraint "ends_on IS NULL OR ends_on >= starts_on", name: "lesson_slots_ends_on_after_starts_on"
    end
  end
end
