class ApplicationMailer < ActionMailer::Base
  # 送信元は Devise のメール（config/initializers/devise.rb の mailer_sender）と同じにする。
  # 本番の送信元アドレス（Amazon SES で確認したもの）は、M7 で設定する。
  default from: "ふりかえ帳 <noreply@example.com>"
  layout "mailer"
end
