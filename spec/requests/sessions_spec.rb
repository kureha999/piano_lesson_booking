require "rails_helper"

RSpec.describe "ログイン・ログアウト（C-01）", type: :request do
  let(:password) { "password123" }

  def log_in(user, pass = password)
    post user_session_path, params: { user: { email: user.email, password: pass } }
  end

  describe "GET /login" do
    it "日本語のログイン画面を表示する" do
      get new_user_session_path

      expect(response).to have_http_status :ok
      expect(response.body).to include "ログイン", "メールアドレス", "パスワード"
    end
  end

  describe "POST /login" do
    it "保護者は P-01（ホーム）に移動する" do
      log_in create(:guardian, password: password)

      expect(response).to redirect_to root_path
      follow_redirect!
      expect(response.body).to include "ホーム", "ログインしました"
    end

    it "先生は T-01（ダッシュボード）に移動する" do
      log_in create(:teacher, password: password)

      expect(response).to redirect_to teacher_root_path
      follow_redirect!
      expect(response.body).to include "ダッシュボード"
    end

    it "パスワードが違うと、同じ画面にエラーを表示する" do
      log_in create(:guardian, password: password), "wrong-password"

      expect(response).to have_http_status :unprocessable_content
      expect(response.body).to include "メールアドレスまたはパスワードが正しくありません"
    end
  end

  describe "ログインしていないとき" do
    it "保護者の画面を開くと C-01 に移動し、ログイン後に元の画面に戻る" do
      guardian = create(:guardian, password: password)

      get root_path
      expect(response).to redirect_to new_user_session_path
      follow_redirect!
      expect(response.body).to include "ログインしてください"

      log_in guardian
      expect(response).to redirect_to root_path
    end

    it "先生の画面を開くと C-01 に移動し、ログイン後に元の画面に戻る" do
      teacher = create(:teacher, password: password)

      get teacher_root_path
      expect(response).to redirect_to new_user_session_path

      log_in teacher
      expect(response).to redirect_to teacher_root_path
    end
  end

  describe "ホーム（P-01）" do
    it "先生が開くと T-01 に移動する" do
      sign_in create(:teacher)

      get root_path

      expect(response).to redirect_to teacher_root_path
    end
  end

  describe "メニュー" do
    it "保護者にはホームとログアウトを表示し、先生用の項目は表示しない" do
      sign_in create(:guardian)

      get root_path

      expect(response.body).to include "ログアウト"
      expect(response.body).not_to include "ダッシュボード"
    end

    it "先生にはダッシュボードとログアウトを表示する" do
      sign_in create(:teacher)

      get teacher_root_path

      expect(response.body).to include "ログアウト", "ダッシュボード"
    end
  end

  describe "DELETE /logout" do
    it "ログアウトして、画面を開くと C-01 に移動する" do
      sign_in create(:guardian)

      delete destroy_user_session_path
      expect(response).to redirect_to root_path

      get root_path
      expect(response).to redirect_to new_user_session_path
    end
  end
end
