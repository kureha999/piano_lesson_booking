require "rails_helper"

RSpec.describe MakeupMailer do
  # 2026年11月2日（月）の朝。11/11（水）16:00〜16:30 のレッスンを欠席し、11/16（月）10:00〜10:30 に振替
  let(:now) { Time.zone.local(2026, 11, 2, 9, 0) }
  let(:student) { create(:student, name: "ひなた", guardian: create(:guardian, name: "山田花子", email: "hanako@example.com")) }
  let(:teacher) { create(:teacher, name: "佐藤先生", email: "teacher@example.com") }
  let(:guardian) { student.guardian }
  let(:credit) { create_credit_for(student, Date.new(2026, 11, 11)) }
  let(:absence) { credit.absence }
  let(:reservation) { create(:makeup_reservation, makeup_credit: credit, makeup_slot: create_makeup_slot(Date.new(2026, 11, 16))) }

  before { travel_to now } # 欠席は、レッスンが始まる前でないと登録できない。let は、使うときに作られる

  def body_of(mail)
    mail.body.to_s
  end

  describe "#absence_received（欠席受付）" do
    context "振替を予約したとき" do
      before { reservation }

      it "保護者に、欠席の受付と、振替の確定を伝える" do
        mail = described_class.absence_received(absence, guardian)

        expect(mail.to).to eq [ "hanako@example.com" ]
        expect(mail.from).to eq [ "noreply@example.com" ]
        expect(mail.subject).to eq "【ふりかえ帳】ひなたさんの欠席を受け付けました（11月11日（水））"
        expect(body_of(mail)).to include "山田花子さん", "ひなたさんについて、お知らせします。",
          "欠席するレッスン：11月11日（水） 16:00〜16:30", "連絡した日時：11月2日 09:00",
          "【振替が確定しました】", "振替：11月16日（月） 10:00〜10:30"
      end

      it "先生に、どの保護者の・どの生徒の欠席かを伝える" do
        mail = described_class.absence_received(absence, teacher)

        expect(mail.to).to eq [ "teacher@example.com" ]
        expect(body_of(mail)).to include "佐藤先生さん", "山田花子さん（保護者）のひなたさんについて", "欠席するレッスン：11月11日（水） 16:00〜16:30",
          "振替：11月16日（月） 10:00〜10:30"
      end
    end

    context "振替を後で選ぶとき" do
      it "保護者には、振替権が付いたことと期限、予定一覧へのリンクを伝える" do
        body = body_of(described_class.absence_received(absence, guardian))

        expect(body).to include "【振替権が付きました】", "2026年12月11日までに、予定一覧から選べます。", "予定一覧：http://example.com/schedule"
        expect(body).not_to include "【振替が確定しました】"
      end

      it "先生には、予定一覧へのリンクを載せない" do
        body = body_of(described_class.absence_received(absence, teacher))

        expect(body).to include "【振替権が付きました】"
        expect(body).not_to include "予定一覧："
      end
    end

    context "振替権が付かないとき" do
      it "締切後の欠席は、その理由を伝える" do
        absence.update!(no_credit_reason: :after_deadline)
        absence.makeup_credit.destroy

        body = body_of(described_class.absence_received(absence.reload, guardian))

        expect(body).to include "【振替権は付きません】", "欠席連絡の締切（レッスン開始の2時間前）を過ぎたため、振替権は付きません。"
        expect(body).not_to include "【振替が確定しました】"
      end

      it "月の上限を超えた欠席は、その理由を伝える" do
        absence.update!(no_credit_reason: :over_monthly_limit)
        absence.makeup_credit.destroy

        expect(body_of(described_class.absence_received(absence.reload, guardian))).to include "今月の振替の上限（2回）に達しているため、振替権は付きません。"
      end
    end
  end

  describe "#makeup_confirmed（振替確定）" do
    it "保護者に、振替の日時と、どの欠席の分かを伝える" do
      mail = described_class.makeup_confirmed(reservation, guardian)

      expect(mail.to).to eq [ "hanako@example.com" ]
      expect(mail.subject).to eq "【ふりかえ帳】ひなたさんの振替が確定しました（11月16日（月））"
      expect(body_of(mail)).to include "山田花子さん", "【振替が確定しました】", "振替：11月16日（月） 10:00〜10:30",
        "欠席したレッスン：11月11日（水） 16:00〜16:30", "予定一覧：http://example.com/schedule"
    end

    it "先生に、保護者と生徒を伝える（予定一覧へのリンクは載せない）" do
      mail = described_class.makeup_confirmed(reservation, teacher)

      expect(mail.to).to eq [ "teacher@example.com" ]
      expect(body_of(mail)).to include "山田花子さん（保護者）のひなたさんについて", "振替：11月16日（月） 10:00〜10:30"
      expect(body_of(mail)).not_to include "予定一覧："
    end
  end

  describe "#makeup_canceled（振替予約のキャンセル）" do
    it "保護者に、キャンセルしたことと、振替権がまた使えることを伝える" do
      mail = described_class.makeup_canceled(reservation, guardian)

      expect(mail.subject).to eq "【ふりかえ帳】ひなたさんの振替予約をキャンセルしました（11月16日（月））"
      expect(body_of(mail)).to include "【振替予約をキャンセルしました】", "キャンセルした振替：11月16日（月） 10:00〜10:30",
        "振替権は、また使えます（2026年12月11日まで）", "予定一覧：http://example.com/schedule"
    end

    it "先生に、枠に空きができたことを伝える" do
      body = body_of(described_class.makeup_canceled(reservation, teacher))

      expect(body).to include "【振替予約をキャンセルしました】", "この枠の予約に、空きができました。"
      expect(body).not_to include "振替権は、また使えます"
    end
  end

  it "本文はテキスト形式で、日本語の件名・本文になっている" do
    mail = described_class.makeup_confirmed(reservation, guardian)

    expect(mail.content_type).to include "text/plain"
    expect(mail.subject).to match(/\A【ふりかえ帳】/)
  end
end
