require "rails_helper"

RSpec.describe "招待メールとパスワード設定（C-02）", type: :request do
  # 先生が生徒を登録したときと同じ方法で、保護者を招待する
  let(:teacher) { create(:teacher) }
  let(:form) { StudentForm.new(name: "たろう", guardian_name: "山田花子", guardian_email: "hanako@example.com", invited_by: teacher) }
  let(:guardian) { form.guardian }
  let(:token) { invitation_link[/invitation_token=(.+)/, 1] }

  # 送られた招待メールから、パスワード設定のリンクを取り出す
  def invitation_link
    ActionMailer::Base.deliveries.last.html_part.body.decoded[%r{http://example\.com/invitation/accept\?invitation_token=[^"\s]+}]
  end

  def set_password(password: "new-password1", confirmation: "new-password1")
    put user_invitation_path, params: { user: { invitation_token: token, password: password, password_confirmation: confirmation } }
  end

  before { form.save }

  describe "招待メール" do
    it "日本語で、宛先・名前・パスワード設定のリンクが書かれている" do
      mail = ActionMailer::Base.deliveries.last

      expect(mail.to).to eq [ "hanako@example.com" ]
      expect(mail.subject).to eq "【ふりかえ帳】パスワードの設定"
      expect(mail.html_part.body.decoded).to include "山田花子さん", "パスワードを設定する", "hanako@example.com"
      expect(mail.text_part.body.decoded).to include "山田花子さん", invitation_link
      expect(invitation_link).to be_present
    end
  end

  describe "GET /invitation/accept（C-02 パスワード設定）" do
    it "メールのリンクから、日本語のパスワード設定画面を表示する" do
      get invitation_link

      expect(response).to have_http_status :ok
      expect(response.body).to include "パスワードの設定", "山田花子さん", "hanako@example.com", "パスワード（確認）", "設定する"
    end

    it "リンクが正しくないときは、ログイン画面に戻してメッセージを表示する" do
      get accept_user_invitation_path(invitation_token: "wrong-token")

      expect(response).to redirect_to new_user_session_path
      follow_redirect!
      expect(response.body).to include "招待のリンクが正しくないか、すでに使われています"
    end
  end

  describe "PUT /invitation（パスワードを設定する）" do
    it "パスワードを設定すると、ログインした状態で P-01 に移動する" do
      set_password

      expect(response).to redirect_to root_path
      follow_redirect!
      expect(response).to have_http_status :ok
      expect(response.body).to include "パスワードを設定しました。", "山田花子"
      expect(guardian.reload).to have_attributes(invitation_accepted_at: be_present)
      expect(guardian).to be_valid_password("new-password1")
    end

    it "設定したパスワードで、あとからログインできる" do
      set_password
      delete destroy_user_session_path

      post user_session_path, params: { user: { email: "hanako@example.com", password: "new-password1" } }

      expect(response).to redirect_to root_path
    end

    it "パスワードが確認と違うときは、同じ画面にエラーを表示し、設定しない" do
      set_password(confirmation: "different")

      expect(response).to have_http_status :unprocessable_content
      expect(response.body).to include "パスワード（確認）", "invalid-feedback"
      expect(guardian.reload.invitation_accepted_at).to be_nil
    end

    it "短すぎるパスワードは、同じ画面にエラーを表示する" do
      set_password(password: "abc", confirmation: "abc")

      expect(response).to have_http_status :unprocessable_content
      expect(response.body).to include "invalid-feedback"
    end

    it "設定したあとは、同じリンクを開けない" do
      set_password
      delete destroy_user_session_path

      get accept_user_invitation_path(invitation_token: token)

      expect(response).to redirect_to new_user_session_path
    end
  end

  describe "パスワードを設定する前" do
    it "推測できないパスワードではログインできず、招待メールからの設定を案内する" do
      post user_session_path, params: { user: { email: "hanako@example.com", password: "password" } }

      expect(response).to have_http_status :unprocessable_content
      expect(response.body).to include "招待メールのリンクから、パスワードを設定してください。"
    end

    it "「パスワードを忘れた方」から設定しても、招待は受け付けた扱いになる" do
      guardian.send_reset_password_instructions
      raw_token = ActionMailer::Base.deliveries.last.body.encoded[/reset_password_token=([^"\s]+)/, 1]

      put user_password_path, params: { user: { reset_password_token: raw_token, password: "new-password1", password_confirmation: "new-password1" } }

      expect(guardian.reload.invitation_accepted_at).to be_present
    end
  end

  describe "使わない機能は 404 にする" do
    it "招待を送る画面・招待の取り消しリンクは開けない（先生でログインしていても）" do
      sign_in teacher

      get new_user_invitation_path
      expect(response).to have_http_status :not_found

      post user_invitation_path, params: { user: { email: "x@example.com" } }
      expect(response).to have_http_status :not_found

      expect { get remove_user_invitation_path(invitation_token: "x") }.not_to change(User, :count)
      expect(response).to have_http_status :not_found
    end
  end
end
