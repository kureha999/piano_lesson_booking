require "rails_helper"

RSpec.describe "振替枠の選択（P-02）", type: :request do
  # 2026年11月2日（月）の朝。欠席するのは、水曜日 16:00〜16:30 のレッスン（11/11）。振替の期限は 12/11
  let(:now) { Time.zone.local(2026, 11, 2, 9, 0) }
  let(:guardian) { create(:guardian) }
  let(:student) { create(:student, guardian: guardian, name: "ひなた") }
  let!(:lesson_slot) { create(:lesson_slot, student: student, wday: 3, start_time: "16:00", end_time: "16:30") }
  let(:lesson_params) { { lesson_slot_id: lesson_slot.id, lesson_on: "2026-11-11" } }

  before { travel_to now }

  def page
    Nokogiri::HTML5.parse(response.body)
  end

  def slot_rows
    page.css("ul.list-group li").map { |li| li.text.squish }
  end

  def open_p02(params = lesson_params, target: student)
    get new_student_absence_path(target), params: params
  end

  context "保護者のとき" do
    before { sign_in guardian }

    describe "予約できる振替枠" do
      it "どのレッスンを欠席するかと、受講できる期間を表示する" do
        open_p02

        expect(response).to have_http_status :ok
        expect(page.at_css("h1").text).to eq "振替の日を選ぶ"
        expect(page.at_css("p").text.squish).to include "ひなたさんの 11月11日（水） 16:00〜16:30 のレッスンを欠席します。"
        expect(page.at_css("p").text.squish).to include "2026年11月12日から2026年12月11日までに受講できる枠から選べます。"
      end

      it "予約できる枠を、日付順に表示する" do
        create_makeup_slot(Date.new(2026, 11, 20))
        create_makeup_slot(Date.new(2026, 11, 16), 15, 30) # 月曜日 15:30
        create_makeup_slot(Date.new(2026, 11, 18))

        open_p02

        expect(slot_rows).to eq [
          "11月16日（月） 15:30〜16:00 （残り1名） この枠にする",
          "11月18日（水） 10:00〜10:30 （残り1名） この枠にする",
          "11月20日（金） 10:00〜10:30 （残り1名） この枠にする"
        ]
      end

      it "ルール外の枠は表示しない（期限後・欠席日より前・定員いっぱいの枠）" do
        ok = create_makeup_slot(Date.new(2026, 11, 16))
        create_makeup_slot(Date.new(2026, 12, 12)) # 期限（12/11）より後
        create_makeup_slot(Date.new(2026, 11, 11), 10) # 欠席日と同じ日（欠席日より前の振替は先取りできない）
        full = create_makeup_slot(Date.new(2026, 11, 17))
        create(:makeup_reservation, makeup_slot: full,
          makeup_credit: create_credit_for(create(:student), Date.new(2026, 11, 9)))

        open_p02

        expect(slot_rows).to eq [ "11月16日（月） 10:00〜10:30 （残り1名） この枠にする" ]
        expect(response.body).to include "11月16日"
        expect(response.body).not_to include "12月12日"
        expect(response.body).not_to include "11月17日"
        expect(ok).to be_present
      end

      it "定員に空きがある枠は、残りの人数を表示する" do
        slot = create_makeup_slot(Date.new(2026, 11, 16), capacity: 3)
        create(:makeup_reservation, makeup_slot: slot, makeup_credit: create_credit_for(create(:student), Date.new(2026, 11, 9)))

        open_p02

        expect(slot_rows).to eq [ "11月16日（月） 10:00〜10:30 （残り2名） この枠にする" ]
      end

      it "その生徒の固定レッスンと時間が重なる枠は表示しない" do
        create_makeup_slot(Date.new(2026, 11, 19), 10) # 木曜日 10:00〜10:30
        create(:lesson_slot, student: student, wday: 4, start_time: "10:00", end_time: "10:30")
        create_makeup_slot(Date.new(2026, 11, 16))

        open_p02

        expect(slot_rows).to eq [ "11月16日（月） 10:00〜10:30 （残り1名） この枠にする" ]
      end
    end

    describe "ボタン" do
      let!(:slot) { create_makeup_slot(Date.new(2026, 11, 16)) }

      it "「この枠にする」は、枠とレッスンを指定して P-03 に進む" do
        open_p02

        form = page.css("form").find { |f| f.at_css("button")&.text == "この枠にする" }
        expect(form["action"]).to eq confirm_student_absences_path(student)
        expect(form["method"]).to eq "get"
        expect(form.css("input[type=hidden]").to_h { |input| [ input["name"], input["value"] ] })
          .to include("lesson_slot_id" => lesson_slot.id.to_s, "lesson_on" => "2026-11-11", "makeup_slot_id" => slot.id.to_s)
      end

      it "「振替は後で選ぶ」は、枠を指定せずに P-03 に進む" do
        open_p02

        form = page.css("form").find { |f| f.at_css("button")&.text == "振替は後で選ぶ" }
        expect(form["action"]).to eq confirm_student_absences_path(student)
        expect(form["method"]).to eq "get"
        hidden = form.css("input[type=hidden]").to_h { |input| [ input["name"], input["value"] ] }
        expect(hidden).to eq("lesson_slot_id" => lesson_slot.id.to_s, "lesson_on" => "2026-11-11")
      end

      it "この画面を開いても、欠席も予約も登録しない" do
        expect { open_p02 }.not_to change { [ Absence.count, MakeupCredit.count, MakeupReservation.count ] }
      end
    end

    describe "予約できる枠がないとき" do
      it "先生が振替枠をまだ登録していなければ、その理由と「振替は後で選ぶ」だけを表示する" do
        open_p02

        expect(response.body).to include "いま選べる振替枠がありません。", "先生が登録した振替枠が、まだありません。"
        expect(page.css("main button").map(&:text)).to eq [ "振替は後で選ぶ" ]
        expect(page.css("ul.list-group")).to be_empty
      end

      it "枠があっても、すべてルール外なら、理由を表示し、選べるのは「振替は後で選ぶ」だけ" do
        create_makeup_slot(Date.new(2026, 12, 12)) # 期限より後
        full = create_makeup_slot(Date.new(2026, 11, 17))
        create(:makeup_reservation, makeup_slot: full, makeup_credit: create_credit_for(create(:student), Date.new(2026, 11, 9)))

        open_p02

        expect(response.body).to include "いま選べる振替枠がありません。"
        expect(response.body).to include "受講できる期間（2026年11月12日〜2026年12月11日）の外の枠があります。"
        expect(response.body).to include "定員に達した枠があります。"
        expect(response.body).not_to include "先生が登録した振替枠が、まだありません。"
        expect(page.css("main button").map(&:text)).to eq [ "振替は後で選ぶ" ]
      end

      it "予約の締切を過ぎた枠だけのときは、その理由を表示する" do
        MakeupRule.current.update!(reservation_deadline_days: 20) # 枠の20日前の 23:59 が締切。11/16 の枠の締切は 10/27 なので、過ぎている
        create_makeup_slot(Date.new(2026, 11, 16))

        open_p02

        expect(response.body).to include "予約の締切を過ぎた枠があります。"
        expect(page.css("main button").map(&:text)).to eq [ "振替は後で選ぶ" ]
      end

      it "ほかのレッスンと重なる枠だけのときは、その理由を表示する" do
        create_makeup_slot(Date.new(2026, 11, 19), 10)
        create(:lesson_slot, student: student, wday: 4, start_time: "10:00", end_time: "10:30")

        open_p02

        expect(response.body).to include "ほかのレッスンと時間が重なる枠があります。"
      end
    end

    describe "振替権が付かない欠席" do
      it "欠席連絡の締切後なら、P-02 を飛ばして P-03 に進む" do
        create_makeup_slot(Date.new(2026, 11, 16))
        travel_to Time.zone.local(2026, 11, 11, 14, 1) # 締切（14:00）の後

        open_p02

        expect(response).to redirect_to confirm_student_absences_path(student, lesson_params)
      end

      it "締切ちょうど（14:00）なら、振替権が付くので P-02 を表示する" do
        travel_to Time.zone.local(2026, 11, 11, 14, 0)

        open_p02

        expect(response).to have_http_status :ok
      end

      it "月の上限を超える欠席なら、P-02 を飛ばして P-03 に進む" do
        create(:absence, lesson_slot: lesson_slot, lesson_on: Date.new(2026, 11, 4), reported_by: guardian)
        create(:absence, lesson_slot: lesson_slot, lesson_on: Date.new(2026, 11, 18), reported_by: guardian)

        open_p02

        expect(response).to redirect_to confirm_student_absences_path(student, lesson_params)
      end
    end

    describe "欠席できないレッスン" do
      it "すでに欠席を連絡したレッスンは、ホームに戻す" do
        create(:absence, lesson_slot: lesson_slot, lesson_on: Date.new(2026, 11, 11), reported_by: guardian)

        open_p02

        expect(response).to redirect_to root_path
        expect(flash[:alert]).to include "このレッスンは欠席を連絡できません。", "すでに欠席を連絡しています"
      end

      it "固定枠の曜日ではない日は、ホームに戻す" do
        open_p02(lesson_params.merge(lesson_on: "2026-11-12"))

        expect(response).to redirect_to root_path
        expect(flash[:alert]).to include "固定枠の曜日（水曜日）ではありません"
      end

      it "もう始まったレッスンは、ホームに戻す" do
        travel_to Time.zone.local(2026, 11, 11, 16, 0)

        open_p02

        expect(response).to redirect_to root_path
        expect(flash[:alert]).to include "すでに始まっています"
      end

      it "日付が正しくなければ、ホームに戻す" do
        open_p02(lesson_params.merge(lesson_on: "not-a-date"))

        expect(response).to redirect_to root_path
        expect(flash[:alert]).to include "このレッスンは欠席を連絡できません。"
      end
    end

    describe "ほかの家庭の子ども" do
      let(:other_student) { create(:student, name: "ほかの子") }
      let!(:other_slot) { create(:lesson_slot, student: other_student, wday: 4, start_time: "17:00", end_time: "17:30") }

      it "ほかの家庭の子どもの画面は開けない（404）" do
        get new_student_absence_path(other_student), params: { lesson_slot_id: other_slot.id, lesson_on: "2026-11-12" }

        expect(response).to have_http_status :not_found
      end

      it "自分の子どもの画面で、ほかの家庭の固定枠を指定しても開けない（404）" do
        open_p02({ lesson_slot_id: other_slot.id, lesson_on: "2026-11-12" })

        expect(response).to have_http_status :not_found
      end
    end
  end

  context "先生のとき" do
    it "ホームに戻す（保護者だけの画面）" do
      sign_in create(:teacher)

      open_p02

      expect(response).to redirect_to teacher_root_path
      expect(flash[:alert]).to eq "この画面を開く権限がありません。"
    end
  end

  context "ログインしていないとき" do
    it "ログイン画面に移動する" do
      open_p02

      expect(response).to redirect_to new_user_session_path
    end
  end
end
