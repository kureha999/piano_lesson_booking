FactoryBot.define do
  factory :absence do
    lesson_slot # 水曜日 16:00〜16:30、2026-04-01 から
    reported_by { lesson_slot.student.guardian }
    lesson_on { Date.new(2099, 1, 7) } # 水曜日。いつ実行しても、レッスンが始まる前になる日
    no_credit_reason { nil }

    trait :after_deadline do
      no_credit_reason { :after_deadline }
    end

    trait :over_monthly_limit do
      no_credit_reason { :over_monthly_limit }
    end
  end
end
