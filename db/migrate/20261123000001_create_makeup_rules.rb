class CreateMakeupRules < ActiveRecord::Migration[8.1]
  def change
    create_table :makeup_rules do |t|
      t.integer :monthly_limit, null: false, default: 2                # 月の上限回数
      t.integer :valid_days, null: false, default: 30                  # 振替の期限（欠席日から何日以内）
      t.integer :absence_deadline_hours, null: false, default: 2       # 欠席連絡の締切（レッスン開始の何時間前）
      t.integer :reservation_deadline_days, null: false, default: 1    # 振替予約の締切（振替枠の何日前の23:59）

      t.timestamps

      # 設定は教室に1行だけ（id = 1 以外は保存できない）。各項目は0以上
      t.check_constraint "id = 1", name: "makeup_rules_single_row"
      t.check_constraint "monthly_limit >= 0", name: "makeup_rules_monthly_limit_non_negative"
      t.check_constraint "valid_days >= 0", name: "makeup_rules_valid_days_non_negative"
      t.check_constraint "absence_deadline_hours >= 0", name: "makeup_rules_absence_deadline_hours_non_negative"
      t.check_constraint "reservation_deadline_days >= 0", name: "makeup_rules_reservation_deadline_days_non_negative"
    end
  end
end
