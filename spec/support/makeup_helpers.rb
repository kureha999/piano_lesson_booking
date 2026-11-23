# 振替の spec で使う、振替権・振替枠を作る道具
module MakeupHelpers
  # 日本時間の日時から、30分の振替枠を作る（先生は1人なので、時間が重なる枠は作れない）
  def create_makeup_slot(date, hour = 10, minute = 0, capacity: 1)
    starts_at = Time.zone.local(date.year, date.month, date.day, hour, minute)
    create(:makeup_slot, starts_at: starts_at, ends_at: starts_at + 30.minutes, capacity: capacity)
  end

  # 生徒の固定枠（欠席日の曜日、16:00〜16:30）で、欠席日に欠席した振替権を作る。期限は欠席日の30日後
  # 固定枠は先生が1人なので重ならないように、生徒ごとに曜日を変えて使う
  def create_credit_for(student, lesson_on)
    slot = student.lesson_slots.find_by(wday: lesson_on.wday) ||
      create(:lesson_slot, student: student, wday: lesson_on.wday, start_time: "16:00", end_time: "16:30")
    absence = create(:absence, lesson_slot: slot, lesson_on: lesson_on)
    create(:makeup_credit, absence: absence)
  end
end

RSpec.configure { |config| config.include MakeupHelpers }
