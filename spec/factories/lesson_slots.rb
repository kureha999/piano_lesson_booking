FactoryBot.define do
  factory :lesson_slot do
    student
    wday { 3 } # 水曜日
    start_time { "16:00" }
    end_time { "16:30" }
    starts_on { Date.new(2026, 4, 1) }
    ends_on { nil }
  end
end
