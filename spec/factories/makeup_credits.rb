FactoryBot.define do
  factory :makeup_credit do
    absence
    student { absence.lesson_slot.student }
    expires_on { absence.lesson_on + 30.days }
  end
end
