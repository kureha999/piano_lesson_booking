FactoryBot.define do
  factory :user, aliases: [ :guardian ] do
    sequence(:email) { |n| "guardian#{n}@example.com" }
    name { "保護者" }
    password { "password123" }
    role { :guardian }

    # create(:teacher) のように使う。先生は1人だけなので、2人作るとエラーになる
    factory :teacher do
      sequence(:email) { |n| "teacher#{n}@example.com" }
      name { "先生" }
      role { :teacher }
    end
  end
end
