require "rails_helper"

RSpec.describe "振替予約のキャンセル（P-05）", type: :request do
  include ActiveJob::TestHelper

  # 2026年11月2日（月）の朝。振替枠は 11/16（月）10:00〜10:30。予約の締切（キャンセルの締切）は、前日（11/15）の23:59まで
  let(:now) { Time.zone.local(2026, 11, 2, 9, 0) }
  let(:guardian) { create(:guardian) }
  let(:student) { create(:student, guardian: guardian, name: "ひなた") }
  let(:credit) { create_credit_for(student, Date.new(2026, 11, 11)) }
  let(:makeup_slot) { create_makeup_slot(Date.new(2026, 11, 16)) }
  let(:reservation) { create(:makeup_reservation, makeup_credit: credit, makeup_slot: makeup_slot) }

  before { travel_to now
reservation  }



  def page
    Nokogiri::HTML5.parse(response.body)
  end

  def makeup_entry
    page.css("section.card ul.list-group").first.css("li").find { |li| li.text.include?("振替（") }
  end

  def cancel_path(target = reservation)
    student_makeup_reservation_cancellation_path(student, target)
  end

  context "保護者のとき" do
    before { sign_in guardian }

    describe "「キャンセル」ボタン（P-05）" do
      it "締切前の振替予約に表示し、確認ダイアログ（Turbo の確認）を付ける" do
        get schedule_path

        form = makeup_entry.at_css("form")
        expect(form["action"]).to eq cancel_path
        expect(form["method"]).to eq "post"
        expect(form["data-turbo-confirm"]).to eq "11月16日（月） 10:00〜10:30の振替予約をキャンセルします。よろしいですか？"
        expect(form.at_css("button").text).to eq "キャンセル"
        expect(makeup_entry.text).not_to include "キャンセルの締切を過ぎました"
      end

      it "締切の直前（11/15 23:59）までは、ボタンを表示する" do
        travel_to Time.zone.local(2026, 11, 15, 23, 59)

        get schedule_path

        expect(makeup_entry.at_css("button").text).to eq "キャンセル"
      end

      it "締切後（11/16 0:00）は、ボタンを表示せず、締切を過ぎたことを表示する" do
        travel_to Time.zone.local(2026, 11, 16, 0, 0)

        get schedule_path

        expect(makeup_entry.at_css("form")).to be_nil
        expect(makeup_entry.text.squish).to include "キャンセルの締切を過ぎました"
      end
    end

    describe "キャンセルする" do
      it "canceled_at を入れて、予定一覧に戻る。行は消さない" do
        post cancel_path

        expect(response).to redirect_to schedule_path
        expect(flash[:notice]).to eq "11月16日（月） 10:00〜10:30の振替予約をキャンセルしました。振替権は、また使えます。"
        expect(reservation.reload.canceled_at).to eq now
        expect(MakeupReservation.count).to eq 1
      end

      it "キャンセル後、予定一覧から予約が消え、振替権が未使用に戻って「振替を選ぶ」が表示される" do
        post cancel_path
        follow_redirect!

        expect(page.css("section.card ul.list-group").first.text).not_to include "11月16日"
        expect(page.css("a.btn").map(&:text)).to include "振替を選ぶ"
        expect(credit.reload.status).to eq :unused
      end

      it "キャンセル後、同じ振替権でほかの枠を予約できる（P-05 → P-02 → P-03 → P-04）" do
        other = create_makeup_slot(Date.new(2026, 11, 18))
        post cancel_path
        follow_redirect!

        get page.at_css("a.btn[href*='makeup_credits']")["href"]
        expect(page.css("ul.list-group li").map { |li| li.text.squish }).to include "11月16日（月） 10:00〜10:30 （残り1名） この枠にする" # キャンセルした枠も選べる
        post student_makeup_credit_makeup_reservations_path(student, credit), params: { makeup_slot_id: other.id }
        follow_redirect!

        expect(page.at_css("h1").text).to eq "振替を予約しました"
        expect(credit.reload.status).to eq :reserved
        expect(credit.active_reservation.makeup_slot).to eq other
        expect(MakeupReservation.where(makeup_credit: credit).count).to eq 2
      end

      it "締切後のリクエストは、サーバー側でも拒否する（予約は有効のまま）" do
        travel_to Time.zone.local(2026, 11, 16, 0, 0)

        post cancel_path

        expect(response).to redirect_to schedule_path
        expect(flash[:alert]).to eq "キャンセルの締切（11月15日 23:59）を過ぎているため、キャンセルできません。先生にご連絡ください。"
        expect(reservation.reload).to be_active
        expect(credit.reload.status).to eq :reserved
      end

      it "枠が始まった後も、拒否する（振替権は使用済みのまま）" do
        travel_to Time.zone.local(2026, 11, 16, 11, 0)

        post cancel_path

        expect(flash[:alert]).to include "キャンセルできません"
        expect(credit.reload.status).to eq :used
      end

      it "すでにキャンセルした予約は、もう一度キャンセルできない" do
        post cancel_path
        first_canceled_at = reservation.reload.canceled_at

        post cancel_path

        expect(flash[:alert]).to eq "この振替予約は、すでにキャンセルされています。"
        expect(reservation.reload.canceled_at).to eq first_canceled_at
      end

      it "キャンセルすると、先生と保護者の両方に、キャンセルのメールを送る" do
        create(:teacher)

        expect { post cancel_path }.to have_enqueued_mail(MakeupMailer, :makeup_canceled).twice
      end

      it "キャンセルできなかったとき（締切後）は、メールを送らない" do
        create(:teacher)
        travel_to Time.zone.local(2026, 11, 16, 0, 0)

        expect { post cancel_path }.not_to have_enqueued_mail(MakeupMailer, :makeup_canceled)
      end

      it "ほかの家庭の振替予約は、キャンセルできない（404）" do
        other = create(:student)
        other_reservation = create(:makeup_reservation, makeup_credit: create_credit_for(other, Date.new(2026, 11, 12)),
          makeup_slot: create_makeup_slot(Date.new(2026, 11, 17)))

        post student_makeup_reservation_cancellation_path(other, other_reservation)

        expect(response).to have_http_status :not_found
        expect(other_reservation.reload).to be_active
      end

      it "自分の子どもの URL に、ほかの家庭の予約を指定しても、キャンセルできない（404）" do
        other = create(:student)
        other_reservation = create(:makeup_reservation, makeup_credit: create_credit_for(other, Date.new(2026, 11, 12)),
          makeup_slot: create_makeup_slot(Date.new(2026, 11, 17)))

        post student_makeup_reservation_cancellation_path(student, other_reservation)

        expect(response).to have_http_status :not_found
        expect(other_reservation.reload).to be_active
      end
    end
  end

  context "先生のとき" do
    it "キャンセルできない（ホームに戻す）" do
      sign_in create(:teacher)

      post cancel_path

      expect(response).to redirect_to teacher_root_path
      expect(reservation.reload).to be_active
    end
  end

  context "ログインしていないとき" do
    it "ログイン画面に移動する" do
      post cancel_path

      expect(response).to redirect_to new_user_session_path
      expect(reservation.reload).to be_active
    end
  end
end
