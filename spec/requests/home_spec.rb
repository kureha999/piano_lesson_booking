require "rails_helper"

RSpec.describe "保護者のホーム（P-01）", type: :request do
  # 2026年6月10日（水）の朝。2026年6月の水曜日は 3・10・17・24 日
  let(:now) { Time.zone.local(2026, 6, 10, 9, 0) }
  let(:guardian) { create(:guardian) }
  let!(:student) { create(:student, guardian: guardian, name: "ひなた") }

  before { travel_to now }

  def page
    Nokogiri::HTML5.parse(response.body)
  end

  # 子どもごとのカード（見出しは「○○さん」）
  def card_of(name)
    page.css("section.card").find { |section| section.at_css("h2").text.strip == "#{name}さん" }
  end

  def lesson_texts(card)
    card.css("ul.list-group").first.css("li").map { |li| li.text.squish }
  end

  # 生徒の曜日・16:00〜16:30 の固定枠（先生は1人なので、重ならないように曜日を変える）
  def create_slot(student, wday, start_time: "16:00", end_time: "16:30")
    create(:lesson_slot, student: student, wday: wday, start_time: start_time, end_time: end_time)
  end

  context "保護者のとき" do
    before { sign_in guardian }

    describe "今後2週間のレッスン" do
      it "今日から14日間（6/10〜6/23）の、まだ始まっていないレッスンを日付順に表示する" do
        create_slot(student, 3) # 水曜日 16:00
        create_slot(student, 6, start_time: "10:00", end_time: "10:30") # 土曜日

        get root_path

        expect(lesson_texts(card_of("ひなた"))).to eq [
          "6月10日（水） 16:00〜16:30 欠席する",
          "6月13日（土） 10:00〜10:30 欠席する",
          "6月17日（水） 16:00〜16:30 欠席する",
          "6月20日（土） 10:00〜10:30 欠席する"
        ]
      end

      it "今日から数えて14日目（6/23）までを表示し、15日目（6/24）は含めない" do
        create_slot(student, 2) # 火曜日

        get root_path

        expect(lesson_texts(card_of("ひなた")).map { |text| text[/\d+月\d+日/] }).to eq %w[6月16日 6月23日]
      end

      it "今日のレッスンは、始まる前なら表示し、始まっていたら表示しない" do
        create_slot(student, 3) # 水曜日 16:00

        travel_to Time.zone.local(2026, 6, 10, 15, 59)
        get root_path
        expect(lesson_texts(card_of("ひなた")).first).to start_with "6月10日（水）"

        travel_to Time.zone.local(2026, 6, 10, 16, 0)
        get root_path
        expect(lesson_texts(card_of("ひなた")).first).to start_with "6月17日（水）"
      end

      it "固定枠の適用期間の外は表示しない（適用終了日を過ぎた枠）" do
        create(:lesson_slot, student: student, wday: 3, ends_on: Date.new(2026, 6, 12))

        get root_path

        expect(lesson_texts(card_of("ひなた"))).to eq [ "6月10日（水） 16:00〜16:30 欠席する" ]
      end

      it "レッスンがないときは、その旨を表示する" do
        get root_path

        expect(card_of("ひなた").text).to include "今後2週間のレッスンはありません。"
      end
    end

    describe "「欠席する」ボタン" do
      it "各レッスンに置き、固定枠と日付を指定した欠席の画面へのリンクにする" do
        slot = create_slot(student, 3)

        get root_path

        link = card_of("ひなた").at_css("li a.btn")
        expect(link.text).to eq "欠席する"
        expect(link["href"]).to eq new_student_absence_path(student, lesson_slot_id: slot.id, lesson_on: "2026-06-10")
        expect(link["aria-label"]).to eq "ひなたさんの6月10日（水）のレッスンを欠席する"
      end

      it "欠席連絡ずみのレッスンには、ボタンの代わりに「欠席連絡ずみ」を表示する" do
        slot = create_slot(student, 3)
        create(:absence, lesson_slot: slot, lesson_on: Date.new(2026, 6, 10), reported_by: guardian)

        get root_path

        items = card_of("ひなた").css("ul.list-group").first.css("li")
        expect(items.first.text.squish).to eq "6月10日（水） 16:00〜16:30 欠席連絡ずみ"
        expect(items.first.at_css("a")).to be_nil
        expect(items.last.at_css("a").text).to eq "欠席する"
      end
    end

    describe "兄弟" do
      it "兄弟がいる保護者は、2人分が分かれて表示される" do
        sibling = create(:student, guardian: guardian, name: "そうた")
        create_slot(student, 3)
        create_slot(sibling, 4, start_time: "17:00", end_time: "17:30") # 木曜日

        get root_path

        expect(page.css("section.card h2").map { |h2| h2.text.strip }).to eq %w[ひなたさん そうたさん]
        expect(lesson_texts(card_of("ひなた")).join).to include "6月10日（水）"
        expect(lesson_texts(card_of("ひなた")).join).not_to include "6月11日（木）"
        expect(lesson_texts(card_of("そうた")).join).to include "6月11日（木） 17:00〜17:30"
        expect(lesson_texts(card_of("そうた")).join).not_to include "6月10日（水）"
      end

      it "振替の残り回数も、子どもごとに数える（兄弟で合算しない）" do
        sibling = create(:student, guardian: guardian, name: "そうた")
        slot = create_slot(student, 3)
        create(:absence, lesson_slot: slot, lesson_on: Date.new(2026, 6, 17), reported_by: guardian)
        create_slot(sibling, 4, start_time: "17:00", end_time: "17:30")

        get root_path

        expect(card_of("ひなた").text.squish).to include "今月の振替の残り：1回"
        expect(card_of("そうた").text.squish).to include "今月の振替の残り：2回"
      end
    end

    describe "ほかの家庭の子ども" do
      it "表示しない（名前も、レッスンも、振替権も）" do
        other = create(:student, name: "ほかの子")
        other_slot = create_slot(other, 4, start_time: "17:00", end_time: "17:30")
        absence = create(:absence, lesson_slot: other_slot, lesson_on: Date.new(2026, 6, 11), reported_by: other.guardian)
        create(:makeup_credit, absence: absence)
        create_slot(student, 3)

        get root_path

        expect(response.body).not_to include "ほかの子"
        expect(response.body).not_to include "17:00"
        expect(page.css("section.card").size).to eq 1
      end
    end

    describe "今月の振替の残り回数" do
      let(:slot) { create_slot(student, 3) }

      def absent(date, *traits)
        create(:absence, *traits, lesson_slot: slot, lesson_on: date, reported_by: guardian)
      end

      def remaining_text
        card_of("ひなた").at_css("p strong").text
      end

      it "欠席がなければ、月の上限（初期値2回）がそのまま残りになる" do
        get root_path

        expect(remaining_text).to eq "2回"
        expect(card_of("ひなた").text.squish).to include "月の上限 2回"
      end

      it "今月に振替権が付いた欠席の数だけ、残りが減る" do
        absent(Date.new(2026, 6, 17))
        get root_path
        expect(remaining_text).to eq "1回"

        absent(Date.new(2026, 6, 24))
        get root_path
        expect(remaining_text).to eq "0回"
      end

      it "先生が上限を減らして、上限より多く振替権が付いていても、0回より小さくならない" do
        absent(Date.new(2026, 6, 17))
        absent(Date.new(2026, 6, 24))
        MakeupRule.current.update!(monthly_limit: 1)

        get root_path

        expect(remaining_text).to eq "0回"
      end

      it "振替権が付かなかった欠席（締切後など）は、数えない" do
        absent(Date.new(2026, 6, 17), :after_deadline)

        get root_path

        expect(remaining_text).to eq "2回"
      end

      it "別の月の欠席は、数えない（月は欠席日で判定する）" do
        absent(Date.new(2026, 7, 1)) # 来月
        get root_path
        expect(remaining_text).to eq "2回"

        travel_to Time.zone.local(2026, 7, 1, 9, 0)
        get root_path
        expect(remaining_text).to eq "1回"
      end

      it "先生が変えた月の上限に従う" do
        MakeupRule.current.update!(monthly_limit: 5)
        absent(Date.new(2026, 6, 17))

        get root_path

        expect(remaining_text).to eq "4回"
      end
    end

    describe "未使用の振替権" do
      let(:slot) { create_slot(student, 3) }

      def credit_for_absence(date)
        create(:makeup_credit, absence: create(:absence, lesson_slot: slot, lesson_on: date, reported_by: guardian))
      end

      it "欠席日と期限を表示する。期限が近い順に並べる" do
        later = credit_for_absence(Date.new(2026, 6, 17))
        earlier = credit_for_absence(Date.new(2026, 6, 24))
        earlier.update!(expires_on: Date.new(2026, 6, 25))
        later.update!(expires_on: Date.new(2026, 7, 17))

        get root_path

        items = card_of("ひなた").css("ul.list-group").last.css("li").map { |li| li.text.squish }
        expect(items).to eq [
          "2026年6月24日の欠席の分 （2026年6月25日まで）",
          "2026年6月17日の欠席の分 （2026年7月17日まで）"
        ]
      end

      it "期限の当日の振替権も表示する" do
        credit_for_absence(Date.new(2026, 6, 17)).update!(expires_on: Date.new(2026, 6, 10))

        get root_path

        expect(card_of("ひなた").text).to include "2026年6月17日の欠席の分"
      end

      it "期限切れ・予約済み・使用済みの振替権は表示しない" do
        credit_for_absence(Date.new(2026, 6, 17)).update!(expires_on: Date.new(2026, 6, 9)) # 期限切れ
        reserved = credit_for_absence(Date.new(2026, 6, 24))
        create(:makeup_reservation, makeup_credit: reserved, makeup_slot: create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 29, 10, 0), ends_at: Time.zone.local(2026, 6, 29, 10, 30)))

        get root_path

        expect(card_of("ひなた").text).to include "未使用の振替権はありません。"
      end

      it "キャンセルして未使用に戻った振替権は表示する" do
        credit = credit_for_absence(Date.new(2026, 6, 17))
        create(:makeup_reservation, :canceled, makeup_credit: credit, makeup_slot: create(:makeup_slot, starts_at: Time.zone.local(2026, 6, 29, 10, 0), ends_at: Time.zone.local(2026, 6, 29, 10, 30)))

        get root_path

        expect(card_of("ひなた").text).to include "2026年6月17日の欠席の分"
      end
    end

    it "お子さんが登録されていない保護者には、その旨を表示する" do
      sign_in create(:guardian)

      get root_path

      expect(response.body).to include "お子さんがまだ登録されていません。"
      expect(page.css("section.card")).to be_empty
    end
  end

  context "先生のとき" do
    it "T-01 に移動する" do
      sign_in create(:teacher)

      get root_path

      expect(response).to redirect_to teacher_root_path
    end
  end

  context "ログインしていないとき" do
    it "ログイン画面に移動する" do
      get root_path

      expect(response).to redirect_to new_user_session_path
    end
  end
end
