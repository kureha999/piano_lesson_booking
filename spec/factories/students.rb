FactoryBot.define do
  factory :student do
    guardian
    sequence(:name) { |n| "生徒#{n}" }
  end
end
