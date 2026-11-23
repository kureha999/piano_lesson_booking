require "rails_helper"

RSpec.describe "未使用の振替権から振替を予約する（P-02〜P-04）", type: :request do
  include ActiveJob::TestHelper

  # 2026年11月2日（月）の朝。11/11（水）の欠席の分の振替権があり、期限は 12/11
  let(:now) { Time.zone.local(2026, 11, 2, 9, 0) }
  let(:guardian) { create(:guardian) }
  let(:student) { create(:student, guardian: guardian, name: "ひなた") }
  let(:credit) { create_credit_for(student, Date.new(2026, 11, 11)) }
  let(:makeup_slot) { create_makeup_slot(Date.new(2026, 11, 16)) } # 月曜日 10:00〜10:30

  # 時刻を合わせた後に、振替権と振替枠を作る（欠席は、レッスンが始まる前でないと登録できない）
  before do
    travel_to now
    credit
    makeup_slot
  end

  def page
    Nokogiri::HTML5.parse(response.body)
  end

  def hidden_fields(form)
    form.css("input[type=hidden]").to_h { |input| [ input["name"], input["value"] ] }.except("authenticity_token")
  end

  def new_path(target_credit = credit)
    new_student_makeup_credit_makeup_reservation_path(student, target_credit)
  end

  context "保護者のとき" do
    before { sign_in guardian }

    describe "P-02 振替枠の選択" do
      it "その振替権で予約できる枠だけを、日付順に表示する" do
        create_makeup_slot(Date.new(2026, 11, 20))
        create_makeup_slot(Date.new(2026, 12, 12)) # 期限より後（表示しない）

        get new_path

        expect(response).to have_http_status :ok
        expect(page.at_css("h1").text).to eq "振替の日を選ぶ"
        expect(page.at_css("p").text.squish).to include "ひなたさんの 11月11日（水） の欠席の分です。",
          "2026年11月12日から2026年12月11日までに受講できる枠から選べます。"
        expect(page.css("ul.list-group li").map { |li| li.text.squish }).to eq [
          "11月16日（月） 10:00〜10:30 （残り1名） この枠にする",
          "11月20日（金） 10:00〜10:30 （残り1名） この枠にする"
        ]
      end

      it "「この枠にする」は、枠を指定して P-03 に進む。「振替は後で選ぶ」は置かない" do
        get new_path

        form = page.css("form").find { |f| f.at_css("button")&.text == "この枠にする" }
        expect(form["action"]).to eq confirm_student_makeup_credit_makeup_reservations_path(student, credit)
        expect(form["method"]).to eq "get"
        expect(hidden_fields(form)).to eq("makeup_slot_id" => makeup_slot.id.to_s)
        expect(page.css("main button").map(&:text)).not_to include "振替は後で選ぶ"
        expect(page.at_css("main a.btn").text).to eq "予定一覧に戻る"
      end

      it "予約できる枠がないときは、その理由を表示する" do
        makeup_slot.destroy
        create_makeup_slot(Date.new(2026, 12, 12)) # 期限より後

        get new_path

        expect(response.body).to include "いま選べる振替枠がありません。", "受講できる期間（2026年11月12日〜2026年12月11日）の外の枠があります。"
        expect(page.css("main button").map(&:text)).to be_empty
      end

      it "すでに予約に使った振替権は、予定一覧に戻す" do
        create(:makeup_reservation, makeup_credit: credit, makeup_slot: makeup_slot)

        get new_path

        expect(response).to redirect_to schedule_path
        expect(flash[:alert]).to eq "この振替権は、すでに予約に使われています。"
      end

      it "期限が切れた振替権は、予定一覧に戻す" do
        travel_to Time.zone.local(2026, 12, 12, 9, 0)

        get new_path

        expect(response).to redirect_to schedule_path
        expect(flash[:alert]).to eq "この振替権は、期限（2026年12月11日）を過ぎています。"
      end

      it "ほかの家庭の子どもの振替権は開けない（404）" do
        other = create(:student)
        other_credit = create_credit_for(other, Date.new(2026, 11, 12))

        get new_student_makeup_credit_makeup_reservation_path(other, other_credit)

        expect(response).to have_http_status :not_found
      end

      it "自分の子どもの URL に、ほかの家庭の振替権を指定しても開けない（404）" do
        other_credit = create_credit_for(create(:student), Date.new(2026, 11, 12))

        get new_student_makeup_credit_makeup_reservation_path(student, other_credit)

        expect(response).to have_http_status :not_found
      end
    end

    describe "P-03 確認" do
      it "確定する内容を表示する" do
        get confirm_student_makeup_credit_makeup_reservations_path(student, credit), params: { makeup_slot_id: makeup_slot.id }

        expect(response).to have_http_status :ok
        expect(page.at_css(".card").text.squish).to include "ひなたさん", "11月11日（水）の欠席の分を、 11月16日（月）に振替",
          "振替：11月16日（月） 10:00〜10:30"
        form = page.at_css("main form")
        expect(form["action"]).to eq student_makeup_credit_makeup_reservations_path(student, credit)
        expect(hidden_fields(form)).to eq("makeup_slot_id" => makeup_slot.id.to_s)
        expect(form.at_css("a")["href"]).to eq new_path
      end

      it "確認しただけでは、予約しない" do
        expect { get confirm_student_makeup_credit_makeup_reservations_path(student, credit), params: { makeup_slot_id: makeup_slot.id } }
          .not_to change(MakeupReservation, :count)
      end

      it "選んだ枠が埋まっていたら、P-02 に戻す" do
        create(:makeup_reservation, makeup_slot: makeup_slot, makeup_credit: create_credit_for(create(:student), Date.new(2026, 11, 9)))

        get confirm_student_makeup_credit_makeup_reservations_path(student, credit), params: { makeup_slot_id: makeup_slot.id }

        expect(response).to redirect_to new_path
        expect(flash[:alert]).to eq "選んだ枠は予約が埋まりました。ほかの枠を選んでください。"
      end

      it "枠を指定しない・存在しない枠のときは、P-02 に戻す" do
        get confirm_student_makeup_credit_makeup_reservations_path(student, credit)
        expect(response).to redirect_to new_path

        get confirm_student_makeup_credit_makeup_reservations_path(student, credit), params: { makeup_slot_id: 0 }
        expect(response).to redirect_to new_path
      end
    end

    describe "P-03 の「確定する」" do
      it "振替予約を作り、P-04 に移動する" do
        expect { post student_makeup_credit_makeup_reservations_path(student, credit), params: { makeup_slot_id: makeup_slot.id } }
          .to change(MakeupReservation, :count).by(1)

        reservation = MakeupReservation.last
        expect(response).to redirect_to student_makeup_credit_makeup_reservation_path(student, credit, reservation)
        expect(reservation).to have_attributes(makeup_credit: credit, makeup_slot: makeup_slot, student: student, canceled_at: nil)
        expect(credit.reload.status).to eq :reserved
      end

      it "直前にほかの人が同じ枠を予約していたら、何も予約せずに P-02 に戻す" do
        create(:makeup_reservation, makeup_slot: makeup_slot, makeup_credit: create_credit_for(create(:student), Date.new(2026, 11, 9)))

        expect { post student_makeup_credit_makeup_reservations_path(student, credit), params: { makeup_slot_id: makeup_slot.id } }
          .not_to change(MakeupReservation, :count)

        expect(response).to redirect_to new_path
        expect(flash[:alert]).to eq "選んだ枠は予約が埋まりました。ほかの枠を選んでください。"
      end

      it "すでに使った振替権では、予約できない（ボタンを2回押したとき）" do
        post student_makeup_credit_makeup_reservations_path(student, credit), params: { makeup_slot_id: makeup_slot.id }

        expect { post student_makeup_credit_makeup_reservations_path(student, credit), params: { makeup_slot_id: makeup_slot.id } }
          .not_to change(MakeupReservation, :count)

        expect(response).to redirect_to schedule_path
        expect(flash[:alert]).to eq "この振替権は、すでに予約に使われています。"
      end
    end

    describe "メール通知（F-12）" do
      before { create(:teacher) }

      # N+1 の検出は外す：メールのジョブは受信者ごとに別のジョブで動くので、まとめて読み込めない
      it "予約すると、先生と保護者の両方に、振替確定のメールを送る", prosopite: false do
        expect { post student_makeup_credit_makeup_reservations_path(student, credit), params: { makeup_slot_id: makeup_slot.id } }
          .to have_enqueued_mail(MakeupMailer, :makeup_confirmed).twice
      end

      it "予約に失敗したとき（枠が先に埋まった）は、メールを送らない" do
        create(:makeup_reservation, makeup_slot: makeup_slot, makeup_credit: create_credit_for(create(:student), Date.new(2026, 11, 9)))

        expect { post student_makeup_credit_makeup_reservations_path(student, credit), params: { makeup_slot_id: makeup_slot.id } }
          .not_to have_enqueued_mail(MakeupMailer, :makeup_confirmed)
      end
    end

    describe "P-04 完了" do
      it "予約した振替枠と、どの欠席の分かを表示する" do
        post student_makeup_credit_makeup_reservations_path(student, credit), params: { makeup_slot_id: makeup_slot.id }
        follow_redirect!

        expect(response).to have_http_status :ok
        expect(page.at_css("h1").text).to eq "振替を予約しました"
        expect(page.at_css(".card").text.squish).to include "ひなたさん", "11月16日（月） 10:00〜10:30 に、振替を予約しました。", "11月11日（水）の欠席の分です。"
        expect(page.css("main a.btn").map { |link| [ link.text, link["href"] ] }).to eq [ [ "予定一覧を見る", schedule_path ], [ "ホームに戻る", root_path ] ]
      end

      it "確認のメールを送ったことを表示する" do
        post student_makeup_credit_makeup_reservations_path(student, credit), params: { makeup_slot_id: makeup_slot.id }
        follow_redirect!

        expect(page.at_css("main").text.squish).to include "確認のメールを、先生とご登録のメールアドレスにお送りしました。"
      end

      it "ほかの振替権の予約は開けない（404）" do
        other_credit = create_credit_for(student, Date.new(2026, 11, 4))
        other = create(:makeup_reservation, makeup_credit: other_credit, makeup_slot: create_makeup_slot(Date.new(2026, 11, 17)))

        get student_makeup_credit_makeup_reservation_path(student, credit, other)

        expect(response).to have_http_status :not_found
      end
    end

    it "「振替は後で選ぶ」にした欠席の振替を、P-05 から予約できる" do
      lesson = student.lesson_slots.first
      # 欠席だけを確定する（振替は後で選ぶ）。11/4 の欠席（振替の期間は 11/5〜12/4 なので、11/16 の枠を選べる）
      post student_absences_path(student), params: { lesson_slot_id: lesson.id, lesson_on: "2026-11-04" }
      later_credit = Absence.find_by!(lesson_on: Date.new(2026, 11, 4)).makeup_credit
      expect(later_credit.status).to eq :unused

      # P-05 の「振替を選ぶ」
      get schedule_path
      href = page.css("a.btn").select { |link| link.text == "振替を選ぶ" }.map { |link| link["href"] }.find { |h| h.include?("/makeup_credits/#{later_credit.id}/") }
      get href
      form = page.css("form").find { |f| f.at_css("button")&.text == "この枠にする" }

      # P-03 → 確定
      get form["action"], params: hidden_fields(form)
      form = page.at_css("main form")
      post form["action"], params: hidden_fields(form)
      follow_redirect!

      expect(page.at_css("h1").text).to eq "振替を予約しました"
      expect(later_credit.reload.status).to eq :reserved
    end
  end

  context "先生のとき" do
    it "ホームに戻す（保護者だけの画面）" do
      sign_in create(:teacher)

      get new_path

      expect(response).to redirect_to teacher_root_path
    end
  end

  context "ログインしていないとき" do
    it "ログイン画面に移動する" do
      get new_path

      expect(response).to redirect_to new_user_session_path
    end
  end
end
