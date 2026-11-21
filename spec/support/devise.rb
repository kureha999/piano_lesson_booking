RSpec.configure do |config|
  # request spec で sign_in(user) を使えるようにする
  config.include Devise::Test::IntegrationHelpers, type: :request
  # view spec で user_signed_in? や current_user を使えるようにする（sign_in(user) でログイン状態にできる）
  config.include Devise::Test::ControllerHelpers, type: :view
end
