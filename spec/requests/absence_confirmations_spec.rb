require "rails_helper"

RSpec.describe "欠席の確認・確定（P-03・P-04）", type: :request do
  include ActiveJob::TestHelper

  # 2026年11月2日（月）の朝。欠席するのは、水曜日 16:00〜16:30 のレッスン（11/11）。振替の期限は 12/11
  let(:now) { Time.zone.local(2026, 11, 2, 9, 0) }
  let(:guardian) { create(:guardian) }
  let(:student) { create(:student, guardian: guardian, name: "ひなた") }
  let!(:lesson_slot) { create(:lesson_slot, student: student, wday: 3, start_time: "16:00", end_time: "16:30") }
  let(:lesson_params) { { lesson_slot_id: lesson_slot.id, lesson_on: "2026-11-11" } }
  let!(:makeup_slot) { create_makeup_slot(Date.new(2026, 11, 16)) } # 月曜日 10:00〜10:30

  before { travel_to now }

  def page
    Nokogiri::HTML5.parse(response.body)
  end

  def hidden_fields(form)
    form.css("input[type=hidden]").to_h { |input| [ input["name"], input["value"] ] }.except("authenticity_token")
  end

  def counts
    [ Absence.count, MakeupCredit.count, MakeupReservation.count ]
  end

  context "保護者のとき" do
    before { sign_in guardian }

    describe "P-03 確認" do
      it "確定する内容を表示する（「○月○日を欠席し、△月△日に振替」）" do
        get confirm_student_absences_path(student), params: lesson_params.merge(makeup_slot_id: makeup_slot.id)

        expect(response).to have_http_status :ok
        expect(page.at_css("h1").text).to eq "内容の確認"
        expect(page.at_css(".card").text.squish).to include "ひなたさん", "11月11日（水）を欠席し、 11月16日（月）に振替"
        expect(page.at_css(".card").text.squish).to include "欠席：11月11日（水） 16:00〜16:30", "振替：11月16日（月） 10:00〜10:30"
        expect(page.css(".alert")).to be_empty
      end

      it "「確定する」は、レッスンと枠を指定して送る。「戻る」は P-02 に戻る" do
        get confirm_student_absences_path(student), params: lesson_params.merge(makeup_slot_id: makeup_slot.id)

        form = page.at_css("main form")
        expect(form["action"]).to eq student_absences_path(student)
        expect(form["method"]).to eq "post"
        expect(hidden_fields(form)).to eq("lesson_slot_id" => lesson_slot.id.to_s, "lesson_on" => "2026-11-11", "makeup_slot_id" => makeup_slot.id.to_s)
        expect(form.at_css("input[type=submit]")["value"]).to eq "確定する"
        expect(form.at_css("a").text).to eq "戻る"
        expect(form.at_css("a")["href"]).to eq new_student_absence_path(student, lesson_params)
      end

      it "確認しただけでは、何も登録しない" do
        expect { get confirm_student_absences_path(student), params: lesson_params.merge(makeup_slot_id: makeup_slot.id) }
          .not_to change { counts }
      end

      it "振替を後で選ぶときは、欠席だけを確定することと、振替権の期限を表示する" do
        get confirm_student_absences_path(student), params: lesson_params

        expect(page.at_css(".card").text.squish).to include "11月11日（水）を欠席します", "振替は後で選びます（2026年12月11日まで"
        expect(hidden_fields(page.at_css("main form"))).to eq("lesson_slot_id" => lesson_slot.id.to_s, "lesson_on" => "2026-11-11")
      end

      it "欠席連絡の締切後は、振替権が付かない理由を表示し、「戻る」はホームに戻る" do
        travel_to Time.zone.local(2026, 11, 11, 14, 1)

        get confirm_student_absences_path(student), params: lesson_params

        expect(page.at_css(".alert").text.squish).to include "欠席連絡の締切（レッスン開始の2時間前）を過ぎたため、振替権は付きません。"
        expect(page.at_css("main form a")["href"]).to eq root_path
        expect(page.at_css(".card").text).not_to include "振替は後で選びます"
      end

      it "月の上限を超える欠席は、その理由を表示する" do
        create(:absence, lesson_slot: lesson_slot, lesson_on: Date.new(2026, 11, 4), reported_by: guardian)
        create(:absence, lesson_slot: lesson_slot, lesson_on: Date.new(2026, 11, 18), reported_by: guardian)

        get confirm_student_absences_path(student), params: lesson_params

        expect(page.at_css(".alert").text.squish).to include "今月の振替の上限（2回）に達しているため、振替権は付きません。"
      end

      it "枠を選んだのに、振替権が付かなくなっていたら、枠なしの確認に戻す" do
        travel_to Time.zone.local(2026, 11, 11, 14, 1)

        get confirm_student_absences_path(student), params: lesson_params.merge(makeup_slot_id: makeup_slot.id)

        expect(response).to redirect_to confirm_student_absences_path(student, lesson_params)
        expect(flash[:alert]).to include "振替権が付かなくなったため"
      end

      it "選んだ枠が埋まっていたら、P-02 に戻し、予約が埋まったことを表示する" do
        create(:makeup_reservation, makeup_slot: makeup_slot, makeup_credit: create_credit_for(create(:student), Date.new(2026, 11, 9)))

        get confirm_student_absences_path(student), params: lesson_params.merge(makeup_slot_id: makeup_slot.id)

        expect(response).to redirect_to new_student_absence_path(student, lesson_params)
        expect(flash[:alert]).to eq "選んだ枠は予約が埋まりました。ほかの枠を選んでください。"
      end

      it "存在しない枠を指定されたら、P-02 に戻す" do
        get confirm_student_absences_path(student), params: lesson_params.merge(makeup_slot_id: 0)

        expect(response).to redirect_to new_student_absence_path(student, lesson_params)
        expect(flash[:alert]).to eq "選んだ枠は予約できなくなりました。ほかの枠を選んでください。"
      end
    end

    describe "P-03 の「確定する」" do
      it "欠席・振替権・振替予約を作り、P-04 に移動する" do
        expect { post student_absences_path(student), params: lesson_params.merge(makeup_slot_id: makeup_slot.id) }
          .to change { counts }.from([ 0, 0, 0 ]).to([ 1, 1, 1 ])

        absence = Absence.last
        expect(response).to redirect_to student_absence_path(student, absence)
        expect(absence).to have_attributes(lesson_slot: lesson_slot, lesson_on: Date.new(2026, 11, 11), reported_by: guardian)
        expect(MakeupReservation.last).to have_attributes(makeup_slot: makeup_slot, student: student)
      end

      it "振替を後で選ぶときは、欠席と振替権だけを作る" do
        expect { post student_absences_path(student), params: lesson_params }.to change { counts }.from([ 0, 0, 0 ]).to([ 1, 1, 0 ])

        expect(response).to redirect_to student_absence_path(student, Absence.last)
      end

      it "振替権が付かない欠席は、欠席だけを作る（理由を残す）" do
        travel_to Time.zone.local(2026, 11, 11, 14, 1)

        expect { post student_absences_path(student), params: lesson_params }.to change { counts }.from([ 0, 0, 0 ]).to([ 1, 0, 0 ])

        expect(Absence.last).to be_after_deadline
      end

      it "直前にほかの人が同じ枠を予約していたら、何も登録せずに P-02 に戻し、メッセージを表示する" do
        create(:makeup_reservation, makeup_slot: makeup_slot, makeup_credit: create_credit_for(create(:student), Date.new(2026, 11, 9)))
        before_counts = counts

        post student_absences_path(student), params: lesson_params.merge(makeup_slot_id: makeup_slot.id)

        expect(response).to redirect_to new_student_absence_path(student, lesson_params)
        expect(flash[:alert]).to eq "選んだ枠は予約が埋まりました。ほかの枠を選んでください。"
        expect(counts).to eq before_counts # 欠席だけが登録されることはない
      end

      it "枠を選んだのに、振替権が付かなくなっていたら、何も登録せずに確認に戻す" do
        travel_to Time.zone.local(2026, 11, 11, 14, 1)

        expect { post student_absences_path(student), params: lesson_params.merge(makeup_slot_id: makeup_slot.id) }
          .not_to change { counts }

        expect(response).to redirect_to confirm_student_absences_path(student, lesson_params)
      end

      it "すでに欠席を連絡したレッスンは、二重に登録せず、ホームに戻す（ボタンを2回押したとき）" do
        post student_absences_path(student), params: lesson_params

        expect { post student_absences_path(student), params: lesson_params }.not_to change { counts }

        expect(response).to redirect_to root_path
      end

      it "確認のあと、確定の直前に欠席を登録できなくなったとき（同時操作）は、何も登録せずにホームに戻す" do
        result = ConfirmAbsence::Result.new(nil, nil, nil, :invalid)
        allow(ConfirmAbsence).to receive(:call).and_return(result)

        expect { post student_absences_path(student), params: lesson_params }.not_to change { counts }

        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq "このレッスンは欠席を連絡できません。"
      end

      it "ほかの家庭の子どもには、確定できない（404）" do
        other = create(:student)
        other_slot = create(:lesson_slot, student: other, wday: 4)

        expect { post student_absences_path(other), params: { lesson_slot_id: other_slot.id, lesson_on: "2026-11-12" } }
          .not_to change { counts }

        expect(response).to have_http_status :not_found
      end
    end

    describe "メール通知（F-12）" do
      before { create(:teacher) }

      # N+1 の検出は外す：メールのジョブは受信者ごとに別のジョブ（本番では別プロセス）で動くので、まとめて読み込めない
      it "確定すると、先生と保護者の両方に、欠席受付のメールを送る", prosopite: false do
        expect { post student_absences_path(student), params: lesson_params.merge(makeup_slot_id: makeup_slot.id) }
          .to have_enqueued_mail(MakeupMailer, :absence_received).twice
      end

      # N+1 の検出は外す：同上
      it "実際に配信すると、先生と保護者のメールアドレスに届く（振替の確定も同じメールで伝える）", prosopite: false do
        perform_enqueued_jobs { post student_absences_path(student), params: lesson_params.merge(makeup_slot_id: makeup_slot.id) }

        mails = ActionMailer::Base.deliveries
        expect(mails.flat_map(&:to)).to contain_exactly(User.teacher.first.email, guardian.email)
        expect(mails.map(&:subject).uniq).to eq [ "【ふりかえ帳】ひなたさんの欠席を受け付けました（11月11日（水））" ]
        expect(mails.map { |mail| mail.body.to_s }).to all(include("振替：11月16日（月） 10:00〜10:30"))
      end

      # N+1 の検出は外す：同上
      it "振替を後で選ぶときも、欠席受付のメールを送る", prosopite: false do
        expect { post student_absences_path(student), params: lesson_params }.to have_enqueued_mail(MakeupMailer, :absence_received).twice
      end

      it "確定に失敗したとき（枠が先に埋まった）は、メールを送らない" do
        create(:makeup_reservation, makeup_slot: makeup_slot, makeup_credit: create_credit_for(create(:student), Date.new(2026, 11, 9)))

        expect { post student_absences_path(student), params: lesson_params.merge(makeup_slot_id: makeup_slot.id) }
          .not_to have_enqueued_mail(MakeupMailer, :absence_received)
      end

      it "確認（P-03）を開いただけでは、メールを送らない" do
        expect { get confirm_student_absences_path(student), params: lesson_params }.not_to have_enqueued_mail
      end
    end

    describe "P-04 完了" do
      def complete(**params)
        post student_absences_path(student), params: lesson_params.merge(params)
        follow_redirect!
      end

      it "振替を予約したときは、欠席の受付と、予約した振替枠を表示する" do
        complete(makeup_slot_id: makeup_slot.id)

        expect(response).to have_http_status :ok
        expect(page.at_css("h1").text).to eq "欠席を受け付けました"
        expect(page.at_css(".card").text.squish).to include "ひなたさん", "11月11日（水） 16:00〜16:30 のレッスンの欠席を受け付けました。",
          "11月16日（月） 10:00〜10:30 に、振替を予約しました。"
      end

      it "振替を後で選んだときは、期限と、あとで選べることを表示する" do
        complete

        expect(page.at_css(".card").text.squish).to include "振替は、まだ選んでいません。2026年12月11日までに、予定一覧から選べます。"
      end

      it "振替権が付かないときは、その理由を表示する" do
        travel_to Time.zone.local(2026, 11, 11, 14, 1)
        complete

        expect(page.at_css(".card").text.squish).to include "欠席連絡の締切（レッスン開始の2時間前）を過ぎたため、振替権は付きません。"
      end

      it "確認のメールを送ったことを表示する" do
        complete

        expect(page.at_css("main").text.squish).to include "確認のメールを、先生とご登録のメールアドレスにお送りしました。"
      end

      it "「ホームに戻る」で P-01 に戻る" do
        complete

        link = page.at_css("main a.btn")
        expect(link.text).to eq "ホームに戻る"
        expect(link["href"]).to eq root_path
      end

      it "ほかの家庭の欠席は開けない（404）" do
        other = create(:student)
        other_absence = create(:absence, lesson_slot: create(:lesson_slot, student: other, wday: 4), lesson_on: Date.new(2026, 11, 12))

        get student_absence_path(student, other_absence)

        expect(response).to have_http_status :not_found
      end
    end

    it "「欠席する」→「枠を選ぶ」→「確定する」の3回の操作で確定できる（P-01 から P-04 まで）" do
      # 1. P-01 の「欠席する」
      get root_path
      href = page.css("li a.btn").find { |link| link["href"].include?("lesson_on=2026-11-11") }["href"]
      get href
      expect(page.at_css("h1").text).to eq "振替の日を選ぶ"

      # 2. P-02 の「この枠にする」
      form = page.css("form").find { |f| f.at_css("button")&.text == "この枠にする" }
      get form["action"], params: hidden_fields(form)
      expect(page.at_css("h1").text).to eq "内容の確認"

      # 3. P-03 の「確定する」
      form = page.at_css("main form")
      post form["action"], params: hidden_fields(form)
      follow_redirect!

      expect(page.at_css("h1").text).to eq "欠席を受け付けました"
      expect(counts).to eq [ 1, 1, 1 ]
    end
  end

  context "先生のとき" do
    it "確認・確定は開けない（ホームに戻す）" do
      sign_in create(:teacher)

      expect { post student_absences_path(student), params: lesson_params }.not_to change { counts }

      expect(response).to redirect_to teacher_root_path
    end
  end

  context "ログインしていないとき" do
    it "ログイン画面に移動する" do
      post student_absences_path(student), params: lesson_params

      expect(response).to redirect_to new_user_session_path
    end
  end
end
