require "rails_helper"

RSpec.describe "固定枠の一覧・登録・変更（T-04・T-05）", type: :request do
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

  describe "T-05 固定枠の登録" do
    let(:student) { create(:student, name: "たろう") }
    let(:valid_params) do
      { lesson_slot: { student_id: student.id, wday: 3, start_time: "16:00", end_time: "16:30", starts_on: "2026-04-01" } }
    end

    context "先生のとき" do
      before { sign_in create(:teacher) }

      it "一覧に「固定枠を追加する」リンクがあり、フォームを表示する" do
        student
        get teacher_lesson_slots_path
        expect(response.body).to include "固定枠を追加する"

        get new_teacher_lesson_slot_path

        expect(response).to have_http_status :ok
        expect(response.body).to include "曜日", "開始時刻", "終了時刻", "適用開始日", "たろう", "保存する"
      end

      it "登録して、一覧に戻る" do
        travel_to Time.zone.local(2026, 6, 10, 12, 0) do
          expect { post teacher_lesson_slots_path, params: valid_params }.to change(LessonSlot, :count).by(1)

          expect(response).to redirect_to teacher_lesson_slots_path
          follow_redirect!
          expect(response.body).to include "たろうさんの固定枠を登録しました。", "水曜日", "16:00〜16:30"
        end
      end

      it "入力エラーは、同じ画面の項目の下に表示し、入力値を残す" do
        expect {
          post teacher_lesson_slots_path, params: { lesson_slot: { student_id: "", wday: "", start_time: "16:30", end_time: "16:00", starts_on: "" } }
        }.not_to change(LessonSlot, :count)

        expect(response).to have_http_status :unprocessable_content
        page = Nokogiri::HTML5.parse(response.body)
        messages = page.css(".invalid-feedback").map { |node| node.text.strip }
        expect(messages).to include "生徒を選んでください", "曜日を入力してください", "終了時刻は開始時刻より後にしてください", "適用開始日を入力してください"
        expect(page.at_css("input[name='lesson_slot[start_time]']")["value"]).to eq "16:30"
      end

      it "時間が重なるときは、エラーを表示する" do
        create(:lesson_slot, wday: 3, start_time: "16:00", end_time: "16:30", starts_on: Date.new(2026, 1, 1))

        expect { post teacher_lesson_slots_path, params: valid_params }.not_to change(LessonSlot, :count)

        expect(response).to have_http_status :unprocessable_content
        expect(response.body).to include "同じ曜日・時間・期間に、ほかの固定枠があります"
      end
    end

    context "保護者のとき" do
      before { sign_in create(:guardian) }

      it "フォームを開けず、登録もできない" do
        get new_teacher_lesson_slot_path
        expect(response).to redirect_to root_path

        expect { post teacher_lesson_slots_path, params: valid_params }.not_to change(LessonSlot, :count)
        expect(response).to redirect_to root_path
      end
    end

    context "ログインしていないとき" do
      it "C-01 に移動し、登録もできない" do
        get new_teacher_lesson_slot_path
        expect(response).to redirect_to new_user_session_path

        expect { post teacher_lesson_slots_path, params: valid_params }.not_to change(LessonSlot, :count)
        expect(response).to redirect_to new_user_session_path
      end
    end
  end

  describe "T-05 固定枠の変更" do
    let!(:slot) { create(:lesson_slot, student: create(:student, name: "たろう"), wday: 3, start_time: "16:00", end_time: "16:30", starts_on: Date.new(2026, 4, 1)) }
    let(:change_params) do
      { lesson_slot: { wday: 4, start_time: "17:00", end_time: "17:30", starts_on: "2026-10-01" } }
    end

    context "先生のとき" do
      before { sign_in create(:teacher) }

      it "一覧に変更のリンクがあり、現在の値が入ったフォームを表示する" do
        get teacher_lesson_slots_path
        expect(response.body).to include edit_teacher_lesson_slot_path(slot)

        get edit_teacher_lesson_slot_path(slot)

        expect(response).to have_http_status :ok
        page = Nokogiri::HTML5.parse(response.body)
        expect(page.at_css("input[name='lesson_slot[start_time]']")["value"]).to eq "16:00"
        expect(page.at_css("select[name='lesson_slot[wday]'] option[selected]").text).to eq "水曜日"
        expect(response.body).to include "たろう", "前日で終了し"
      end

      it "変更すると、今の枠に適用終了日が入り、新しい枠ができる（今の枠の曜日・時間は変わらない）" do
        travel_to Time.zone.local(2026, 6, 10, 12, 0) do
          expect { patch teacher_lesson_slot_path(slot), params: change_params }.to change(LessonSlot, :count).by(1)

          expect(response).to redirect_to teacher_lesson_slots_path
          follow_redirect!
          expect(response.body).to include "たろうさんの固定枠を変更しました。", "2026年10月1日から新しい枠"
          expect(slot.reload).to have_attributes(wday: 3, ends_on: Date.new(2026, 9, 30))
          expect(slot.time_range).to eq "16:00〜16:30"
          expect(LessonSlot.order(:id).last).to have_attributes(wday: 4, starts_on: Date.new(2026, 10, 1), student: slot.student)
        end
      end

      it "変更後は、開始日になるまで古い枠が一覧に出て、開始日からは新しい枠が出る" do
        patch teacher_lesson_slot_path(slot), params: change_params

        travel_to Time.zone.local(2026, 9, 30, 12, 0) do
          get teacher_lesson_slots_path
          expect(Nokogiri::HTML5.parse(response.body).css("tbody tr td:first-child").map { |td| td.text.strip }).to eq [ "水曜日" ]
        end
        travel_to Time.zone.local(2026, 10, 1, 12, 0) do
          get teacher_lesson_slots_path
          expect(Nokogiri::HTML5.parse(response.body).css("tbody tr td:first-child").map { |td| td.text.strip }).to eq [ "木曜日" ]
        end
      end

      it "曜日・時間が変わらないときは、何も保存せず、その旨を表示する" do
        expect {
          patch teacher_lesson_slot_path(slot), params: { lesson_slot: { wday: 3, start_time: "16:00", end_time: "16:30", starts_on: "2026-10-01" } }
        }.not_to change(LessonSlot, :count)

        follow_redirect!
        expect(response.body).to include "変更がありませんでした"
        expect(slot.reload.ends_on).to be_nil
      end

      it "生徒は、変更できない（パラメーターで送られても、無視する）" do
        other = create(:student)

        patch teacher_lesson_slot_path(slot), params: { lesson_slot: change_params[:lesson_slot].merge(student_id: other.id) }

        expect(LessonSlot.order(:id).last.student).to eq slot.student
      end

      it "時間が重なるときは、エラーを表示し、今の枠も変えない" do
        create(:lesson_slot, wday: 4, start_time: "17:00", end_time: "17:30", starts_on: Date.new(2026, 1, 1))

        expect { patch teacher_lesson_slot_path(slot), params: change_params }.not_to change(LessonSlot, :count)

        expect(response).to have_http_status :unprocessable_content
        expect(response.body).to include "同じ曜日・時間・期間に、ほかの固定枠があります"
        expect(slot.reload.ends_on).to be_nil
      end

      it "適用開始日が今の枠より前なら、エラーを表示する" do
        patch teacher_lesson_slot_path(slot), params: { lesson_slot: change_params[:lesson_slot].merge(starts_on: "2026-03-01") }

        expect(response).to have_http_status :unprocessable_content
        expect(response.body).to include "今の枠の適用開始日（2026年4月1日）より後にしてください"
      end

      it "終了済みの枠は、変更画面を開けず、404（E-01）になる" do
        ended = create(:lesson_slot, wday: 1, starts_on: Date.new(2025, 1, 1), ends_on: Date.new(2025, 12, 31))

        get edit_teacher_lesson_slot_path(ended)

        expect(response).to have_http_status :not_found
      end

      it "存在しない枠は、404（E-01）になる" do
        patch teacher_lesson_slot_path(0), params: change_params

        expect(response).to have_http_status :not_found
      end
    end

    context "保護者のとき" do
      let(:guardian) { create(:guardian) }

      before { sign_in guardian }

      it "自分の子どもの枠でも、変更画面は開けず、変更もできない" do
        mine = create(:lesson_slot, student: create(:student, guardian: guardian), wday: 1)

        get edit_teacher_lesson_slot_path(mine)
        expect(response).to redirect_to root_path

        expect { patch teacher_lesson_slot_path(mine), params: change_params }.not_to change(LessonSlot, :count)
        expect(mine.reload.ends_on).to be_nil
      end

      it "ほかの家庭の枠は、404 になり、存在することも伝えない" do
        get edit_teacher_lesson_slot_path(slot)

        expect(response).to have_http_status :not_found
      end
    end

    context "ログインしていないとき" do
      it "C-01 に移動する" do
        get edit_teacher_lesson_slot_path(slot)

        expect(response).to redirect_to new_user_session_path
      end
    end
  end
end
