require "rails_helper"

RSpec.describe "振替枠の一覧（T-06）", type: :request do
  describe "GET /teacher/makeup_slots" do
    context "先生のとき" do
      before { sign_in create(:teacher) }

      def rows
        Nokogiri::HTML5.parse(response.body).css("tbody tr").map { |tr| tr.css("td").map { |td| td.text.strip } }
      end

      it "これからの振替枠を、日付順に、日付・時間・定員・予約数の欄で表示する" do
        travel_to Time.zone.local(2026, 6, 10, 12, 0) do
          create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 20, 10, 0), ends_at: Time.zone.local(2026, 6, 20, 10, 30), capacity: 2)
          create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 13, 15, 0), ends_at: Time.zone.local(2026, 6, 13, 15, 30), capacity: 1)

          get teacher_makeup_slots_path

          expect(response).to have_http_status :ok
          expect(response.body).to include "予約数"
          expect(rows).to eq [
            [ "2026年6月13日（土）", "15:00〜15:30", "1人", "—" ],
            [ "2026年6月20日（土）", "10:00〜10:30", "2人", "—" ]
          ]
        end
      end

      it "過去の振替枠は表示しない（終了前の枠は、開始後でも表示する）" do
        travel_to Time.zone.local(2026, 6, 10, 12, 0) do
          create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 9, 10, 0), ends_at: Time.zone.local(2026, 6, 9, 10, 30))
          create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 10, 10, 0), ends_at: Time.zone.local(2026, 6, 10, 11, 0)) # 終了済み
          create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 10, 11, 0), ends_at: Time.zone.local(2026, 6, 10, 11, 45)) # 終了済み
          create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 10, 11, 45), ends_at: Time.zone.local(2026, 6, 10, 12, 15)) # 開催中
          create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 11, 10, 0), ends_at: Time.zone.local(2026, 6, 11, 10, 30))

          get teacher_makeup_slots_path

          expect(rows.map(&:second)).to eq %w[11:45〜12:15 10:00〜10:30]
        end
      end

      it "振替枠がないときは、その旨を表示する" do
        get teacher_makeup_slots_path

        expect(response.body).to include "これからの振替枠はありません。"
      end

      it "メニューに「振替枠」を表示する" do
        get teacher_makeup_slots_path

        expect(Nokogiri::HTML5.parse(response.body).css("a.nav-link").map(&:text)).to include "振替枠"
      end
    end

    context "保護者のとき" do
      before { sign_in create(:guardian) }

      it "一覧を表示せず、P-01 に戻してメッセージを表示する" do
        get teacher_makeup_slots_path

        expect(response).to redirect_to root_path
        follow_redirect!
        expect(response.body).to include "この画面を開く権限がありません。"
      end
    end

    context "ログインしていないとき" do
      it "C-01 に移動する" do
        get teacher_makeup_slots_path

        expect(response).to redirect_to new_user_session_path
      end
    end
  end
end
