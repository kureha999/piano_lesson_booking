require "rails_helper"

RSpec.describe "権限管理", type: :request do
  describe "保護者が先生の画面（T-01）を URL で直接開いたとき" do
    before { sign_in create(:guardian) }

    it "画面を表示せず、P-01 に戻してメッセージを表示する" do
      get teacher_root_path

      expect(response).to redirect_to root_path
      follow_redirect!
      expect(response.body).to include "この画面を開く権限がありません。"
      expect(response.body).not_to include "ダッシュボード"
    end

    it "先生用のメニューは表示しない" do
      get teacher_root_path
      follow_redirect!

      expect(response.body).not_to include teacher_root_path
    end
  end

  describe "先生" do
    before { sign_in create(:teacher) }

    it "T-01 を開ける" do
      get teacher_root_path

      expect(response).to have_http_status :ok
      expect(response.body).to include "ダッシュボード"
    end
  end

  describe "ログインしていないとき" do
    it "先生の画面を開くと、権限のメッセージではなく C-01 に移動する" do
      get teacher_root_path

      expect(response).to redirect_to new_user_session_path
    end
  end
end
