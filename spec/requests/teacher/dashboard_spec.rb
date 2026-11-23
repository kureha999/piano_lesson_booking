require "rails_helper"

RSpec.describe "先生のダッシュボード（T-01）", type: :request do
  # 2026年11月9日（月）の朝。今週は 11/9（月）〜11/15（日）
  let(:now) { Time.zone.local(2026, 11, 9, 8, 0) }
  let(:guardian) { create(:guardian, name: "山田花子") }
  let(:student) { create(:student, guardian: guardian, name: "ひなた") }

  before { travel_to now }

  def page
    Nokogiri::HTML5.parse(response.body)
  end

  def rows
    page.css("tbody tr").map { |tr| tr.css("td").map { |td| td.text.squish } }
  end

  def absence_on(date, *traits, kid: student)
    slot = kid.lesson_slots.find_by(wday: date.wday) || create(:lesson_slot, student: kid, wday: date.wday, start_time: "16:00", end_time: "16:30")
    create(:absence, *traits, lesson_slot: slot, lesson_on: date, reported_by: kid.guardian)
  end

  context "先生のとき" do
    before { sign_in create(:teacher) }

    it "今週の範囲を表示する" do
      get teacher_root_path

      expect(response).to have_http_status :ok
      heading = page.css("h2").find { |h2| h2.text == "今週の欠席・振替" }
      expect(heading.next_element.text.squish).to eq "11月9日（月）〜11月15日（日）"
    end

    it "今週の欠席と振替予約を、日付順に表示する" do
      credit = create(:makeup_credit, absence: absence_on(Date.new(2026, 11, 10)))
      create(:makeup_reservation, makeup_credit: credit, makeup_slot: create_makeup_slot(Date.new(2026, 11, 13), 10))
      absence_on(Date.new(2026, 11, 12))

      get teacher_root_path

      expect(rows).to eq [
        [ "11月10日（火） 16:00〜16:30", "ひなた", "山田花子", "欠席 （振替：11月13日（金） 10:00〜10:30）" ],
        [ "11月12日（木） 16:00〜16:30", "ひなた", "山田花子", "欠席 （振替は未選択）" ],
        [ "11月13日（金） 10:00〜10:30", "ひなた", "山田花子", "振替 （11月10日（火）の欠席の分）" ]
      ]
    end

    it "締切後の欠席は「当日欠席」と表示する" do
      absence_on(Date.new(2026, 11, 10), :after_deadline)

      get teacher_root_path

      expect(rows).to eq [ [ "11月10日（火） 16:00〜16:30", "ひなた", "山田花子", "当日欠席 （振替権なし）" ] ]
      expect(page.at_css(".badge.text-bg-danger").text).to eq "当日欠席"
    end

    it "通常の欠席・月の上限を超えた欠席には「当日欠席」を付けない" do
      absence_on(Date.new(2026, 11, 10))
      absence_on(Date.new(2026, 11, 11), :over_monthly_limit)

      get teacher_root_path

      expect(rows.map(&:last)).to eq [ "欠席 （振替は未選択）", "欠席 （月の上限を超えたため、振替権なし）" ]
      expect(response.body).not_to include "当日欠席"
    end

    it "今週以外の欠席・キャンセルした振替予約は表示しない" do
      absence_on(Date.new(2026, 11, 16)) # 来週
      credit = create(:makeup_credit, absence: absence_on(Date.new(2026, 11, 11)))
      create(:makeup_reservation, :canceled, makeup_credit: credit, makeup_slot: create_makeup_slot(Date.new(2026, 11, 13), 10))

      get teacher_root_path

      expect(rows.size).to eq 1
      expect(response.body).not_to include "11月16日"
      expect(response.body).not_to include "11月13日"
    end

    it "兄弟など、複数の生徒の分を、生徒と保護者の名前つきで表示する" do
      other = create(:student, name: "ほかの子", guardian: create(:guardian, name: "鈴木一郎"))
      absence_on(Date.new(2026, 11, 10))
      absence_on(Date.new(2026, 11, 11), kid: other)

      get teacher_root_path

      expect(rows.map { |row| row[1..2] }).to eq [ %w[ひなた 山田花子], %w[ほかの子 鈴木一郎] ]
    end

    it "今週の欠席・振替がないときは、その旨を表示する" do
      get teacher_root_path

      expect(response.body).to include "今週の欠席・振替はありません。"
      expect(page.css("table")).to be_empty
    end
  end

  describe "初期設定の残り手順" do
    before { sign_in create(:teacher) }

    def setup_card
      page.at_css("section[aria-labelledby='setup-heading']")
    end

    def step_links
      setup_card.css("li a").to_h { |link| [ link.text, link["href"] ] }
    end

    it "何も登録していないときは、4つの手順を、各画面へのリンクつきで表示する" do
      get teacher_root_path

      expect(setup_card.at_css("h2").text).to eq "初期設定の残り手順"
      expect(step_links).to eq(
        "① 生徒を登録する" => new_teacher_student_path,
        "② 固定枠を設定する" => new_teacher_lesson_slot_path,
        "② 振替枠を登録する" => new_teacher_makeup_slot_path,
        "③ 振替ルールを確認する" => edit_teacher_makeup_rule_path
      )
    end

    it "終わった手順は完了の表示にし、リンクを外す。残りの手順だけリンクにする" do
      create(:lesson_slot) # 生徒と固定枠が終わる

      get teacher_root_path

      expect(step_links.keys).to eq [ "② 振替枠を登録する", "③ 振替ルールを確認する" ]
      done = setup_card.css("li").first(2).map { |li| li.text.squish }
      expect(done).to eq [ "✓ ① 生徒を登録する（完了）", "✓ ② 固定枠を設定する（完了）" ]
    end

    it "振替ルールは、保存すると完了になる（行がない間は初期値で動くが、未完了と表示する）" do
      get teacher_root_path
      expect(step_links.keys).to include "③ 振替ルールを確認する"

      patch teacher_makeup_rule_path, params: { makeup_rule: { monthly_limit: "2", valid_days: "30", absence_deadline_hours: "2", reservation_deadline_days: "1" } }
      get teacher_root_path

      expect(step_links.keys).not_to include "③ 振替ルールを確認する"
    end

    it "すべて終わると、手順の表示が消える" do
      create(:lesson_slot)
      create(:makeup_slot)
      MakeupRule.current.save!

      get teacher_root_path

      expect(setup_card).to be_nil
      expect(response.body).not_to include "初期設定の残り手順"
      expect(page.at_css("h1").text).to eq "ダッシュボード"
    end

    it "手順の表示の有無にかかわらず、今週の欠席・振替は表示する" do
      get teacher_root_path

      expect(response.body).to include "今週の欠席・振替"
    end
  end

  context "保護者のとき" do
    it "開けない（ホームに戻す）" do
      sign_in guardian

      get teacher_root_path

      expect(response).to redirect_to root_path
    end
  end
end
