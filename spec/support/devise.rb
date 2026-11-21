RSpec.configure do |config|
  # request spec で sign_in(user) を使えるようにする
  config.include Devise::Test::IntegrationHelpers, type: :request
  # controller spec・view spec で sign_in(user)・current_user を使えるようにする
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Devise::Test::ControllerHelpers, type: :view
end
