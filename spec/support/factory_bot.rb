RSpec.configure do |config|
  # create(:user) のように FactoryBot. を付けずに書けるようにする
  config.include FactoryBot::Syntax::Methods
end
