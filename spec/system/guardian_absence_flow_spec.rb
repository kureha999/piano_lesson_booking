require "rails_helper"

# 画面遷移図②（保護者：欠席から振替の確定まで）を、ブラウザ（Chrome）で通しで確認する。
# 日付は、今日を基準に作る（レッスンは3日後、振替枠はその1週間後）。
RSpec.describe "保護者の欠席と振替の流れ", type: :system do
  include ActiveJob::TestHelper

  let(:helpers) { ApplicationController.helpers }
  let(:lesson_on) { Date.current + 3 }
  let(:makeup_on) { lesson_on + 7 }
  let(:guardian) { create(:guardian, name: "山田花子", email: "hanako@example.com") }
  let!(:student) { create(:student, guardian: guardian, name: "ひなた") }
  let!(:makeup_slot) { create_makeup_slot(makeup_on) } # 10:00〜10:30
  let(:lesson_label) { "ひなたさんの#{helpers.japanese_date_with_wday(lesson_on)}のレッスンを欠席する" }

  before { create(:lesson_slot, student: student, wday: lesson_on.wday, start_time: "16:00", end_time: "16:30") }


  # 振替枠の表示（「6月10日（水） 10:00〜10:30」）
  def makeup_slot_text
    helpers.makeup_slot_text(makeup_slot)
  end

  def log_in(user)
    visit root_path
    expect(page).to have_css "h1", text: "ログイン"
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button "ログイン"
  end

  it "ログイン → 欠席 → 振替枠の選択 → 確定 → 完了（3回の操作で確定する）" do
    log_in(guardian)

    # P-01 ホーム
    expect(page).to have_css "h1", text: "ホーム"
    expect(page).to have_content "ひなたさん"
    click_on lesson_label

    # P-02 振替枠の選択
    expect(page).to have_css "h1", text: "振替の日を選ぶ"
    expect(page).to have_content makeup_slot_text
    click_on "この枠にする"

    # P-03 確認（この時点では、まだ何も登録しない）
    expect(page).to have_css "h1", text: "内容の確認"
    expect(page).to have_content "#{helpers.japanese_date_with_wday(lesson_on)}を欠席し"
    expect(page).to have_content "#{helpers.japanese_date_with_wday(makeup_on)}に振替"
    expect(Absence.count).to eq 0
    click_on "確定する"

    # P-04 完了
    expect(page).to have_css "h1", text: "欠席を受け付けました"
    expect(page).to have_content "#{makeup_slot_text} に、振替を予約しました。"
    expect(page).to have_content "確認のメールを、先生とご登録のメールアドレスにお送りしました。"
    expect(Absence.count).to eq 1
    expect(MakeupReservation.active.where(makeup_slot: makeup_slot).count).to eq 1

    # P-01 に戻ると、欠席連絡ずみになる
    click_on "ホームに戻る"
    expect(page).to have_css "h1", text: "ホーム"
    expect(page).to have_content "欠席連絡ずみ"
    expect(page).to have_no_link lesson_label
  end

  it "欠席の連絡と振替の予約を、ログアウトしても保持している（ログアウト → 再ログイン）" do
    log_in(guardian)
    click_on lesson_label
    click_on "この枠にする"
    click_on "確定する"
    expect(page).to have_css "h1", text: "欠席を受け付けました"

    click_on "ログアウト"
    expect(page).to have_css "h1", text: "ログイン"

    log_in(guardian)
    click_on "予定一覧"
    expect(page).to have_content "振替（#{helpers.japanese_date_with_wday(lesson_on)}の欠席の分）"
  end

  it "間違ったパスワードではログインできない" do
    visit root_path
    fill_in "user_email", with: guardian.email
    fill_in "user_password", with: "wrong-password"
    click_button "ログイン"

    expect(page).to have_css "h1", text: "ログイン"
    expect(page).to have_no_css "h1", text: "ホーム"
  end

  describe "振替は後で選ぶ → 予定一覧から予約 → キャンセル" do
    it "欠席だけを先に連絡し、あとで予定一覧から振替を予約して、キャンセルすると振替権が戻る" do
      sign_in guardian
      visit root_path

      # P-02 → P-03：振替は後で選ぶ
      click_on lesson_label
      click_on "振替は後で選ぶ"
      expect(page).to have_css "h1", text: "内容の確認"
      expect(page).to have_content "振替は後で選びます"
      click_on "確定する"

      # P-04：振替権だけが付く
      expect(page).to have_css "h1", text: "欠席を受け付けました"
      expect(page).to have_content "振替は、まだ選んでいません。"
      expect(MakeupCredit.count).to eq 1
      expect(MakeupReservation.count).to eq 0

      # P-05 予定一覧：未使用の振替権から予約する
      click_on "予定一覧"
      expect(page).to have_css "h1", text: "予定一覧"
      expect(page).to have_content "未使用の振替権"
      click_on "振替を選ぶ"

      expect(page).to have_css "h1", text: "振替の日を選ぶ"
      click_on "この枠にする"
      expect(page).to have_css "h1", text: "内容の確認"
      click_on "確定する"

      expect(page).to have_css "h1", text: "振替を予約しました"
      expect(page).to have_content makeup_slot_text
      expect(MakeupReservation.active.count).to eq 1

      # P-05：予約が予定に出て、「キャンセル」できる
      click_on "予定一覧を見る"
      expect(page).to have_content "振替（#{helpers.japanese_date_with_wday(lesson_on)}の欠席の分）"
      expect(page).to have_no_content "未使用の振替権の分"

      # 確認ダイアログ（D-01）が出る。いったん閉じると、キャンセルされない
      dismiss_confirm("#{makeup_slot_text}の振替予約をキャンセルします。よろしいですか？") { click_on "キャンセル" }
      expect(MakeupReservation.active.count).to eq 1

      # 「OK」で、キャンセルされる
      accept_confirm { click_on "キャンセル" }
      expect(page).to have_content "の振替予約をキャンセルしました。振替権は、また使えます。"
      expect(MakeupReservation.active.count).to eq 0
      expect(page).to have_link "振替を選ぶ" # 振替権が未使用に戻る
    end
  end
end
