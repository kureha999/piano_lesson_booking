require "rails_helper"

RSpec.describe "パスワード再設定（C-03・C-04）", type: :request do
  let(:user) { create(:guardian, name: "山田花子", password: "old-password") }

  # 送られた再設定メールから、リンクの URL を取り出す
  def reset_link_from(mail)
    mail.body.encoded[%r{http://example\.com/password/edit\?reset_password_token=[^"\s]+}]
  end

  describe "C-03 申請" do
    it "日本語の申請画面を表示し、ログイン画面からリンクされている" do
      get new_user_session_path
      expect(response.body).to include "パスワードを忘れた方"

      get new_user_password_path
      expect(response).to have_http_status :ok
      expect(response.body).to include "パスワードの再設定", "送信する"
    end

    it "登録済みのメールアドレスなら、日本語の再設定メールを送る" do
      expect {
        post user_password_path, params: { user: { email: user.email } }
      }.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(response).to redirect_to new_user_session_path
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq [ user.email ]
      expect(mail.subject).to eq "【ふりかえ帳】パスワードの再設定"
      expect(mail.body.encoded).to include "山田花子さん", "パスワードを再設定する"
    end

    it "未登録のメールアドレスでも、同じ表示にしてメールは送らない（登録の有無を知らせない）" do
      expect {
        post user_password_path, params: { user: { email: "nobody@example.com" } }
      }.not_to change { ActionMailer::Base.deliveries.size }

      expect(response).to redirect_to new_user_session_path
      follow_redirect!
      expect(response.body).to include "登録されているメールアドレスの場合は"
    end
  end

  describe "C-04 新しいパスワードの入力" do
    def request_reset
      post user_password_path, params: { user: { email: user.email } }
      reset_link_from(ActionMailer::Base.deliveries.last)
    end

    it "メールのリンクから新しいパスワードを設定し、ログインできる" do
      link = request_reset

      get link
      expect(response).to have_http_status :ok
      expect(response.body).to include "新しいパスワードの入力", "変更する"

      token = Rack::Utils.parse_query(URI(link).query)["reset_password_token"]
      put user_password_path, params: { user: {
        reset_password_token: token, password: "new-password", password_confirmation: "new-password"
      } }
      expect(response).to redirect_to new_user_session_path
      follow_redirect!
      expect(response.body).to include "パスワードを変更しました"

      post user_session_path, params: { user: { email: user.email, password: "old-password" } }
      expect(response).to have_http_status :unprocessable_content

      post user_session_path, params: { user: { email: user.email, password: "new-password" } }
      expect(response).to redirect_to root_path
    end

    it "確認用のパスワードが違うと、同じ画面に日本語のエラーを表示する" do
      token = Rack::Utils.parse_query(URI(request_reset).query)["reset_password_token"]

      put user_password_path, params: { user: {
        reset_password_token: token, password: "new-password", password_confirmation: "different"
      } }

      expect(response).to have_http_status :unprocessable_content
      expect(response.body).to include "パスワード（確認）とパスワードの入力が一致しません"
    end

    it "リンクが正しくないと、エラーを表示する" do
      put user_password_path, params: { user: {
        reset_password_token: "invalid", password: "new-password", password_confirmation: "new-password"
      } }

      expect(response).to have_http_status :unprocessable_content
      expect(response.body).to include "再設定のリンク"
    end

    it "有効期間（6時間）を過ぎたリンクは使えない" do
      link = request_reset
      token = Rack::Utils.parse_query(URI(link).query)["reset_password_token"]

      travel 7.hours do
        put user_password_path, params: { user: {
          reset_password_token: token, password: "new-password", password_confirmation: "new-password"
        } }

        expect(response).to have_http_status :unprocessable_content
        expect(response.body).to include "有効期限が切れています"
      end
    end

    it "メールのリンクを経由せずに開くと、ログイン画面に戻す" do
      get edit_user_password_path

      expect(response).to redirect_to new_user_session_path
    end
  end
end
