require "rails_helper"

RSpec.describe "予定一覧（P-05）", type: :request do
  # 2026年11月2日（月）の朝。2026年11月の水曜日は 4・11・18・25 日
  let(:now) { Time.zone.local(2026, 11, 2, 9, 0) }
  let(:guardian) { create(:guardian) }
  let!(:student) { create(:student, guardian: guardian, name: "ひなた") }

  before { travel_to now }

  def page
    Nokogiri::HTML5.parse(response.body)
  end

  def card_of(name)
    page.css("section.card").find { |section| section.at_css("h2").text.strip == "#{name}さん" }
  end

  def entries_of(name)
    card_of(name).css("ul.list-group").first.css("li").map { |li| li.text.squish }
  end

  def create_slot(student, wday, start_time: "16:00", end_time: "16:30")
    create(:lesson_slot, student: student, wday: wday, start_time: start_time, end_time: end_time)
  end

  context "保護者のとき" do
    before { sign_in guardian }

    describe "子どもごとの予定" do
      it "固定レッスンと振替予約を、日付順に並べて表示する" do
        slot = create_slot(student, 3)
        absence = create(:absence, lesson_slot: slot, lesson_on: Date.new(2026, 11, 4), reported_by: guardian)
        credit = create(:makeup_credit, absence: absence)
        create(:makeup_reservation, makeup_credit: credit, makeup_slot: create_makeup_slot(Date.new(2026, 11, 16)))

        get schedule_path

        expect(response).to have_http_status :ok
        expect(entries_of("ひなた").first(4)).to eq [
          "11月4日（水） 16:00〜16:30 欠席連絡ずみ",
          "11月11日（水） 16:00〜16:30 固定レッスン",
          "11月16日（月） 10:00〜10:30 振替（11月4日（水）の欠席の分） キャンセル",
          "11月18日（水） 16:00〜16:30 固定レッスン"
        ]
      end

      it "今日から8週間（56日）先までのレッスンを表示する（12/23 まで。12/30 は含めない）" do
        create_slot(student, 3)

        get schedule_path

        dates = entries_of("ひなた").map { |text| text[/\d+月\d+日/] }
        expect(dates.first).to eq "11月4日"
        expect(dates.last).to eq "12月23日"
        expect(dates.size).to eq 8
      end

      it "始まったレッスンと、終わった振替は表示しない" do
        create_slot(student, 3)
        slot = create_makeup_slot(Date.new(2026, 11, 3))
        credit = create_credit_for(student, Date.new(2026, 11, 4))
        create(:makeup_reservation, makeup_credit: credit, makeup_slot: slot)
        travel_to Time.zone.local(2026, 11, 4, 16, 0) # 11/4 のレッスンの開始ちょうど

        get schedule_path

        expect(entries_of("ひなた").first).to start_with "11月11日（水）"
        expect(card_of("ひなた").text).not_to include "11月3日"
      end

      it "キャンセルした振替予約は表示しない" do
        create_slot(student, 3)
        credit = create_credit_for(student, Date.new(2026, 11, 4))
        create(:makeup_reservation, :canceled, makeup_credit: credit, makeup_slot: create_makeup_slot(Date.new(2026, 11, 16)))

        get schedule_path

        expect(card_of("ひなた").text).not_to include "11月16日"
      end

      it "予定がないときは、その旨を表示する" do
        get schedule_path

        expect(card_of("ひなた").text).to include "今後8週間の予定はありません。"
      end
    end

    describe "兄弟とほかの家庭" do
      it "兄弟は子どもごとに分けて表示し、ほかの家庭の子どもは表示しない" do
        sibling = create(:student, guardian: guardian, name: "そうた")
        create_slot(student, 3)
        create_slot(sibling, 4, start_time: "17:00", end_time: "17:30")
        other = create(:student, name: "ほかの子")
        create_slot(other, 5, start_time: "18:00", end_time: "18:30")

        get schedule_path

        expect(page.css("section.card h2").map { |h2| h2.text.strip }).to eq %w[ひなたさん そうたさん]
        expect(entries_of("ひなた").join).to include "16:00"
        expect(entries_of("ひなた").join).not_to include "17:00"
        expect(entries_of("そうた").join).to include "11月5日（木） 17:00〜17:30"
        expect(response.body).not_to include "ほかの子"
        expect(response.body).not_to include "18:00"
      end

      it "お子さんが登録されていない保護者には、その旨を表示する" do
        sign_in create(:guardian)

        get schedule_path

        expect(response.body).to include "お子さんがまだ登録されていません。"
      end
    end

    describe "未使用の振替権" do
      before { create_slot(student, 3) }

      it "欠席日と期限を表示し、「振替を選ぶ」から P-02 に移動できる" do
        credit = create_credit_for(student, Date.new(2026, 11, 11))

        get schedule_path

        list = card_of("ひなた").css("ul.list-group").last
        expect(list.text.squish).to include "2026年11月11日の欠席の分 （2026年12月11日まで）"
        link = list.at_css("a.btn")
        expect(link.text).to eq "振替を選ぶ"
        expect(link["href"]).to eq new_student_makeup_credit_makeup_reservation_path(student, credit)
      end

      it "期限切れ・予約ずみ・使用ずみの振替権は表示しない" do
        create_credit_for(student, Date.new(2026, 11, 4)).update!(expires_on: Date.new(2026, 11, 1)) # 期限切れ
        reserved = create_credit_for(student, Date.new(2026, 11, 11))
        create(:makeup_reservation, makeup_credit: reserved, makeup_slot: create_makeup_slot(Date.new(2026, 11, 16)))

        get schedule_path

        expect(card_of("ひなた").text).to include "未使用の振替権はありません。"
        expect(page.css("a.btn").map(&:text)).not_to include "振替を選ぶ"
      end
    end

    it "メニューの「予定一覧」から開ける" do
      get root_path

      expect(page.css("a.nav-link").find { |link| link.text.strip == "予定一覧" }["href"]).to eq schedule_path
    end
  end

  context "先生のとき" do
    it "ホームに戻す（保護者だけの画面）" do
      sign_in create(:teacher)

      get schedule_path

      expect(response).to redirect_to teacher_root_path
      expect(flash[:alert]).to eq "この画面を開く権限がありません。"
    end
  end

  context "ログインしていないとき" do
    it "ログイン画面に移動する" do
      get schedule_path

      expect(response).to redirect_to new_user_session_path
    end
  end
end
