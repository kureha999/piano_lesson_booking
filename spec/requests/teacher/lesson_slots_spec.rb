require "rails_helper"

RSpec.describe "固定枠の一覧（T-04）", type: :request do
  describe "GET /teacher/lesson_slots" do
    context "先生のとき" do
      before { sign_in create(:teacher) }

      def rows
        Nokogiri::HTML5.parse(response.body).css("tbody tr").map { |tr| tr.css("td")[0, 3].map { |td| td.text.strip } }
      end

      it "今日に有効な固定枠を、曜日・開始時刻の順に表示する" do
        travel_to Time.zone.local(2026, 6, 10, 12, 0) do
          create(:lesson_slot, student: create(:student, name: "水曜の後"), wday: 3, start_time: "17:00", end_time: "17:30")
          create(:lesson_slot, student: create(:student, name: "水曜の前"), wday: 3, start_time: "16:00", end_time: "16:30")
          create(:lesson_slot, student: create(:student, name: "土曜"), wday: 6, start_time: "10:00", end_time: "10:30")
          create(:lesson_slot, student: create(:student, name: "月曜"), wday: 1, start_time: "18:00", end_time: "18:30")

          get teacher_lesson_slots_path

          expect(response).to have_http_status :ok
          expect(rows).to eq [
            %w[月曜日 18:00〜18:30 月曜], %w[水曜日 16:00〜16:30 水曜の前],
            %w[水曜日 17:00〜17:30 水曜の後], %w[土曜日 10:00〜10:30 土曜]
          ]
        end
      end

      it "適用終了日を過ぎた枠と、まだ始まっていない枠は表示しない（終了日の当日は表示する）" do
        travel_to Time.zone.local(2026, 6, 10, 12, 0) do
          create(:lesson_slot, student: create(:student, name: "終了日の当日"), wday: 1, ends_on: Date.new(2026, 6, 10))
          create(:lesson_slot, student: create(:student, name: "終了済み"), wday: 2, ends_on: Date.new(2026, 6, 9))
          create(:lesson_slot, student: create(:student, name: "これから始まる"), wday: 3, starts_on: Date.new(2026, 6, 11))
          create(:lesson_slot, student: create(:student, name: "終わりなし"), wday: 4, starts_on: Date.new(2026, 1, 1))

          get teacher_lesson_slots_path

          expect(rows.map(&:last)).to eq %w[終了日の当日 終わりなし]
        end
      end

      it "今日は日本時間で判定する（日本時間の 0 時過ぎは、UTC ではまだ前日）" do
        # 日本時間 2026-06-11 00:30 = UTC 2026-06-10 15:30
        travel_to Time.utc(2026, 6, 10, 15, 30) do
          create(:lesson_slot, student: create(:student, name: "昨日まで"), ends_on: Date.new(2026, 6, 10))

          get teacher_lesson_slots_path

          expect(rows).to be_empty
        end
      end

      it "適用期間（開始日と、終了日または「終了日なし」）を表示する" do
        create(:lesson_slot, wday: 1, starts_on: Date.new(2026, 4, 1), ends_on: Date.new(2099, 9, 30))
        create(:lesson_slot, wday: 2, starts_on: Date.new(2026, 4, 1), ends_on: nil)

        get teacher_lesson_slots_path

        expect(response.body).to include "2026年4月1日から", "2099年9月30日まで", "終了日なし"
      end

      it "固定枠がないときは、その旨を表示する" do
        get teacher_lesson_slots_path

        expect(response.body).to include "まだ固定枠が登録されていません。"
      end

      it "メニューに「固定枠」を表示する" do
        get teacher_lesson_slots_path

        expect(Nokogiri::HTML5.parse(response.body).css("a.nav-link").map(&:text)).to include "固定枠"
      end
    end

    context "保護者のとき" do
      before { sign_in create(:guardian) }

      it "一覧を表示せず、P-01 に戻してメッセージを表示する" do
        get teacher_lesson_slots_path

        expect(response).to redirect_to root_path
        follow_redirect!
        expect(response.body).to include "この画面を開く権限がありません。"
      end
    end

    context "ログインしていないとき" do
      it "C-01 に移動する" do
        get teacher_lesson_slots_path

        expect(response).to redirect_to new_user_session_path
      end
    end
  end
end
