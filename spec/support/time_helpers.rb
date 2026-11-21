RSpec.configure do |config|
  # travel・travel_to で、時間を進めたテストを書けるようにする（期限のテストなどで使う）
  config.include ActiveSupport::Testing::TimeHelpers
end
