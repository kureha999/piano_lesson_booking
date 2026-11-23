FactoryBot.define do
  factory :makeup_reservation do
    makeup_credit
    makeup_slot
    student { makeup_credit.student }
    canceled_at { nil }

    # キャンセルした予約（行は残る）
    trait :canceled do
      canceled_at { Time.zone.local(2026, 6, 1, 9, 0) }
    end
  end
end
