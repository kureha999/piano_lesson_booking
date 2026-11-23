require "rails_helper"

# 画面遷移図③（先生：初期設定と日常の操作）を、ブラウザ（Chrome）で通しで確認する。
# ダッシュボードの手順（① 生徒 → ② 固定枠・振替枠 → ③ 振替ルール）のとおりに進める。
RSpec.describe "先生の初期設定の流れ", type: :system do
  include ActiveJob::TestHelper

  let!(:teacher) { create(:teacher, email: "teacher@example.com") }
  let(:makeup_on) { Date.current + 5 }

  def log_in_as_teacher
    visit root_path
    fill_in "user_email", with: teacher.email
    fill_in "user_password", with: "password123"
    click_button "ログイン"
  end

  it "ログイン → 生徒の登録 → 固定枠 → 振替枠 → ルールの確認（ダッシュボードの手順が順に完了する）" do
    log_in_as_teacher

    # T-01：初期設定の4つの手順が、すべて残っている
    expect(page).to have_css "h1", text: "ダッシュボード"
    expect(page).to have_content "初期設定の残り手順"
    expect(page).to have_link "① 生徒を登録する"

    # ① T-03 生徒の登録 → T-02 生徒一覧
    click_on "① 生徒を登録する"
    fill_in "生徒の呼び名", with: "ひなた"
    fill_in "保護者のメールアドレス", with: "hanako@example.com"
    fill_in "保護者の名前", with: "山田花子"
    click_button "登録する"

    expect(page).to have_css "h1", text: "生徒一覧"
    expect(page).to have_content "ひなた"
    expect(page).to have_content "山田花子"
    expect(Student.pluck(:name)).to eq %w[ひなた]
    expect(ActionMailer::Base.deliveries.map(&:to).flatten).to include "hanako@example.com" # 保護者に招待メール

    # ② T-05 固定枠の登録 → T-04 固定枠の一覧
    click_on "ダッシュボード"
    expect(page).to have_no_link "① 生徒を登録する"
    click_on "② 固定枠を設定する"
    select "ひなた", from: "生徒"
    select "水曜日", from: "曜日"
    fill_in "開始時刻", with: Time.zone.local(2000, 1, 1, 16, 0)
    fill_in "終了時刻", with: Time.zone.local(2000, 1, 1, 16, 30)
    fill_in "適用開始日", with: Date.current
    click_button "保存する"

    expect(page).to have_css "h1", text: "固定枠"
    expect(page).to have_content "水曜日"
    expect(page).to have_content "16:00〜16:30"
    expect(page).to have_content "ひなた"
    expect(LessonSlot.count).to eq 1

    # ② T-07 振替枠の登録 → T-06 振替枠の一覧
    click_on "ダッシュボード"
    click_on "② 振替枠を登録する"
    fill_in "開始日時", with: Time.zone.local(makeup_on.year, makeup_on.month, makeup_on.day, 10, 0)
    fill_in "終了日時", with: Time.zone.local(makeup_on.year, makeup_on.month, makeup_on.day, 10, 30)
    fill_in "定員", with: 2
    click_button "保存する"

    expect(page).to have_css "h1", text: "振替枠"
    expect(page).to have_content "10:00〜10:30"
    expect(MakeupSlot.pick(:capacity)).to eq 2

    # ③ T-08 振替ルールの確認 → 保存する（保存後は T-08 のまま。README 12-5③ は T-01 に戻る図だが、現在の実装に合わせる）
    click_on "ダッシュボード"
    click_on "③ 振替ルールを確認する"
    expect(page).to have_css "h1", text: "振替ルール"
    expect(find_field("月の上限回数").value).to eq "2" # 初期値が入っている
    fill_in "月の上限回数", with: 3
    click_button "保存する"

    expect(page).to have_content "振替ルールを保存しました。"
    expect(MakeupRule.pick(:monthly_limit)).to eq 3

    # すべて終わると、ダッシュボードの残り手順のカードは消える
    click_on "ダッシュボード"
    expect(page).to have_css "h1", text: "ダッシュボード"
    expect(page).to have_no_content "初期設定の残り手順"
  end

  it "入力に誤りがあると、同じ画面に理由を表示し、何も登録しない" do
    sign_in teacher
    visit new_teacher_student_path

    click_button "登録する"

    expect(page).to have_css "h1", text: "生徒の登録"
    expect(page).to have_css ".invalid-feedback, .text-danger", minimum: 1
    expect(Student.count).to eq 0
  end
end
