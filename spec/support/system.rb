# system spec（ブラウザでの操作の確認）の設定。ブラウザは headless（画面を出さない）の Chrome を、Cuprite（CDP で直接操作）で動かす。
# Chrome が入っている環境（GitHub Actions の ubuntu-latest・手元の Mac）で動く。ChromeDriver は使わない。
require "capybara/rspec"
require "capybara/cuprite"

Capybara.server = :puma, { Silent: true }
Capybara.default_max_wait_time = 5
Capybara.enable_aria_label = true # 「欠席する」「キャンセル」など、aria-label で区別しているボタンを、その名前で探せるようにする

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [ 1280, 1000 ], headless: true, process_timeout: 20,
    browser_options: ENV["CI"] ? { "no-sandbox" => nil } : {})
end

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :cuprite }

  # system spec で sign_in(user)（ログイン画面を通さないログイン）を使えるようにする
  config.include Devise::Test::IntegrationHelpers, type: :system
end
