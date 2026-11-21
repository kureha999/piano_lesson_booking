require "rails_helper"

RSpec.describe "生徒一覧（T-02）", type: :request do
  describe "GET /teacher/students" do
    context "先生のとき" do
      before { sign_in create(:teacher) }

      it "生徒名と保護者名を一覧で表示する" do
        yamada = create(:guardian, name: "山田花子")
        suzuki = create(:guardian, name: "鈴木一郎")
        create(:student, guardian: yamada, name: "たろう")
        create(:student, guardian: yamada, name: "はなこ")
        create(:student, guardian: suzuki, name: "ゆうき")

        get teacher_students_path

        expect(response).to have_http_status :ok
        rows = Nokogiri::HTML5.parse(response.body).css("tbody tr").map { |tr| tr.css("td").map { |td| td.text.strip } }
        expect(rows).to eq [ %w[たろう 山田花子], %w[はなこ 山田花子], %w[ゆうき 鈴木一郎] ]
      end

      it "生徒がいないときは、その旨を表示する" do
        get teacher_students_path

        expect(response.body).to include "まだ生徒が登録されていません。"
        expect(response.body).not_to include "<table"
      end

      it "メニューに「生徒」を表示する" do
        get teacher_students_path

        expect(Nokogiri::HTML5.parse(response.body).css("#main-menu .nav-link").map(&:text).map(&:strip))
          .to include "生徒"
      end
    end

    context "保護者のとき" do
      before { sign_in create(:guardian) }

      it "一覧を表示せず、P-01 に戻してメッセージを表示する" do
        create(:student, name: "ひみつ")

        get teacher_students_path

        expect(response).to redirect_to root_path
        follow_redirect!
        expect(response.body).to include "この画面を開く権限がありません。"
        expect(response.body).not_to include "ひみつ"
      end
    end

    context "ログインしていないとき" do
      it "C-01 に移動する" do
        get teacher_students_path

        expect(response).to redirect_to new_user_session_path
      end
    end
  end
end
