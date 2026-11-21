FactoryBot.define do
  factory :makeup_slot do
    # 重ならないように、連番ごとに1日ずつずらす（2026-06-01 の 10:00〜10:30 から）
    sequence(:starts_at) { |n| Time.zone.local(2026, 6, 1, 10, 0) + (n - 1).days }
    ends_at { starts_at + 30.minutes }
    capacity { 1 }
  end
end
