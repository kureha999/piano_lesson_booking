require "rails_helper"

# bin/rails db:seed で作るデモデータで、すべての画面にデータが表示されることを確かめる（#53 の完了条件）
RSpec.describe "デモデータの画面表示", type: :request do
  # 2026年11月11日（水）の朝。今週は 11/9（月）〜11/15（日）
  let(:now) { Time.zone.local(2026, 11, 11, 10, 0) }

  before do
    travel_to now
    # データの作成（1件ずつ検証しながら保存する）は、N+1 の検出から外す。画面を開くところから検出する（#56）
    Prosopite.pause { DemoData.load(today: now.to_date) }
  end

  def page
    Nokogiri::HTML5.parse(response.body)
  end

  def table_rows
    page.css("tbody tr").map { |tr| tr.css("td").map { |td| td.text.squish } }
  end

  def cards
    page.css("section.card").to_h { |section| [ section.at_css("h2").text.strip, section.text.squish ] }
  end

  describe "ログイン" do
    it "デモ用のアカウントとパスワード（password123）でログインできる（先生・保護者）" do
      { "teacher@demo.example.com" => teacher_root_path, "hanako@demo.example.com" => root_path }.each do |email, path|
        new_scan("POST /login #{email}")
        post user_session_path, params: { user: { email: email, password: "password123" } }

        expect(response).to redirect_to path
        delete destroy_user_session_path
      end
    end
  end

  describe "先生の画面" do
    before { sign_in User.find_by!(email: "teacher@demo.example.com") }

    it "T-01：今週の欠席と振替が表示される（当日欠席を含む）。初期設定の手順は表示されない" do
      get teacher_root_path

      expect(response.body).not_to include "初期設定の残り手順"
      expect(table_rows).to eq [
        [ "11月10日（火） 16:00〜16:30", "ゆうき", "鈴木 一郎", "当日欠席 （振替権なし）" ],
        [ "11月11日（水） 16:00〜16:30", "ひなた", "山田 花子", "欠席 （振替：11月21日（土） 10:00〜10:30）" ],
        [ "11月12日（木） 17:00〜17:30", "みさき", "田中 恵", "欠席 （振替は未選択）" ]
      ]
    end

    it "T-02：4人の生徒と、今月の振替の利用回数が表示される" do
      get teacher_students_path

      expect(table_rows.map { |row| row[0, 3] }).to eq [
        [ "ひなた", "山田 花子", "2回 （上限 2回）" ], [ "そうた", "山田 花子", "1回 （上限 2回）" ],
        [ "ゆうき", "鈴木 一郎", "1回 （上限 2回）" ], [ "みさき", "田中 恵", "1回 （上限 2回）" ]
      ]
    end

    it "T-04：固定枠（4件）が表示される" do
      get teacher_lesson_slots_path

      expect(table_rows.map { |row| row[0, 3] }).to eq [
        [ "火曜日", "16:00〜16:30", "ゆうき" ], [ "水曜日", "16:00〜16:30", "ひなた" ],
        [ "水曜日", "16:30〜17:00", "そうた" ], [ "木曜日", "17:00〜17:30", "みさき" ]
      ]
    end

    it "T-06：これからの振替枠と、予約の状況が表示される" do
      get teacher_makeup_slots_path

      expect(response).to have_http_status :ok
      expect(table_rows.size).to eq 5 # 先週の枠（終わった枠）を除く
      expect(response.body).to include "11月21日"
    end

    it "T-03・T-05・T-07・T-08：登録・設定の画面が開ける（振替ルールは初期値で表示）" do
      [ new_teacher_student_path, new_teacher_lesson_slot_path, new_teacher_makeup_slot_path, edit_teacher_makeup_rule_path ].each do |path|
        new_scan("GET #{path}")
        get path

        expect(response).to have_http_status :ok
      end
      expect(page.at_css("input[name='makeup_rule[monthly_limit]']")["value"]).to eq "2"
    end
  end

  describe "先生の編集画面（N+1 の確認）" do
    before { sign_in User.find_by!(email: "teacher@demo.example.com") }

    it "T-03・T-05・T-07：デモデータの全件の編集画面が、N+1 なしで開ける" do
      paths = Student.all.map { |student| edit_teacher_student_path(student) } +
        LessonSlot.all.map { |slot| edit_teacher_lesson_slot_path(slot) } +
        MakeupSlot.upcoming.map { |slot| edit_teacher_makeup_slot_path(slot) }

      paths.each do |path|
        new_scan("GET #{path}")
        get path

        expect(response).to have_http_status :ok
      end
      expect(paths.size).to be > 10
    end
  end

  describe "保護者（山田 花子：ひなた・そうた）の画面" do
    before { sign_in User.find_by!(email: "hanako@demo.example.com") }

    it "P-01：兄弟2人が分かれて表示され、レッスン・残り回数・未使用の振替権がある" do
      get root_path

      expect(cards.keys).to eq %w[ひなたさん そうたさん]
      expect(cards["ひなたさん"]).to include "今月の振替の残り：0回", "11月11日（水） 16:00〜16:30 欠席連絡ずみ", "11月18日（水） 16:00〜16:30 欠席する"
      expect(cards["そうたさん"]).to include "今月の振替の残り：1回", "11月11日（水） 16:30〜17:00 欠席する", "2026年11月4日の欠席の分"
    end

    it "P-05：振替予約（キャンセルできる）と、未使用の振替権（振替を選ぶ）が表示される" do
      get schedule_path

      expect(cards["ひなたさん"]).to include "11月21日（土） 10:00〜10:30 振替（11月11日（水）の欠席の分） キャンセル"
      expect(cards["そうたさん"]).to include "2026年11月4日の欠席の分", "振替を選ぶ"
    end

    it "ひなたは今月の振替の上限に達しているため、欠席すると P-02 を飛ばして P-03 に進む（振替権は付かない）" do
      get root_path
      href = page.css("li a.btn").find { |link| link["href"].include?("lesson_on=2026-11-18") && link["aria-label"].include?("ひなた") }["href"]

      get href
      follow_redirect!

      expect(page.at_css("h1").text).to eq "内容の確認"
      expect(page.at_css(".alert").text.squish).to include "今月の振替の上限（2回）に達しているため、振替権は付きません。"
    end

    it "P-02 → P-03 → P-04：「欠席する」から、デモデータの振替枠を選んで確定できる（そうた）" do
      get root_path
      href = page.css("li a.btn").find { |link| link["href"].include?("lesson_on=2026-11-18") && link["aria-label"].include?("そうた") }["href"]
      get href
      expect(page.at_css("h1").text).to eq "振替の日を選ぶ"
      expect(page.css("ul.list-group li").size).to be >= 1

      form = page.css("form").find { |f| f.at_css("button")&.text == "この枠にする" }
      get form["action"], params: form.css("input[type=hidden]").to_h { |i| [ i["name"], i["value"] ] }
      expect(page.at_css("h1").text).to eq "内容の確認"

      form = page.at_css("main form")
      post form["action"], params: form.css("input[type=hidden]").to_h { |i| [ i["name"], i["value"] ] }
      follow_redirect!
      expect(page.at_css("h1").text).to eq "欠席を受け付けました"
    end

    it "P-05 から、未使用の振替権で振替枠を選べる" do
      get schedule_path
      href = page.css("a.btn").find { |link| link.text == "振替を選ぶ" }["href"]

      get href

      expect(page.at_css("h1").text).to eq "振替の日を選ぶ"
      expect(page.css("ul.list-group li").size).to be >= 1
    end
  end

  describe "ほかの保護者の画面" do
    it "鈴木 一郎：ゆうきの予定と、未使用の振替権が表示される" do
      sign_in User.find_by!(email: "ichiro@demo.example.com")

      get root_path

      expect(cards.keys).to eq %w[ゆうきさん]
      expect(cards["ゆうきさん"]).to include "11月17日（火） 16:00〜16:30 欠席する", "2026年11月3日の欠席の分"
      expect(response.body).not_to include "ひなた"
    end

    it "田中 恵：みさきの予定が表示される（今週の欠席は、振替が未選択のまま）" do
      sign_in User.find_by!(email: "megumi@demo.example.com")

      get schedule_path

      expect(cards["みさきさん"]).to include "11月12日（木） 17:00〜17:30 欠席連絡ずみ", "2026年11月12日の欠席の分", "振替を選ぶ"
    end
  end
end
