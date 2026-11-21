class CreateMakeupSlots < ActiveRecord::Migration[8.1]
  def change
    create_table :makeup_slots do |t|
      t.datetime :starts_at, null: false # 開始日時
      t.datetime :ends_at, null: false   # 終了日時
      t.integer :capacity, null: false, default: 1 # 定員

      t.timestamps

      t.check_constraint "ends_at > starts_at", name: "makeup_slots_ends_after_starts"
      t.check_constraint "capacity >= 1", name: "makeup_slots_capacity_positive"
      # 先生は1人なので、振替枠どうしの時間は重ならない（同時に登録されても、DB が止める）。
      # 終了日時と次の開始日時が同じ（続けて並ぶ）枠は、重ならない扱い（tsrange は終わりを含まない）
      t.exclusion_constraint "tsrange(starts_at, ends_at) WITH &&", using: :gist, name: "makeup_slots_no_overlap"
    end
  end
end
