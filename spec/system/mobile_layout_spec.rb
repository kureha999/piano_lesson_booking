require "rails_helper"

# スマホの幅（iPhone SE 相当の 375px）で、すべての画面が、横にはみ出さずに表示されることを確かめる（#58 の事前確認）。
# 実機の確認の代わりではない（実機でしか分からない、タップのしやすさ・文字の読みやすさ・ソフトウェアキーボードなどは README の確認表で確かめる）。
RSpec.describe "スマホ幅の表示", type: :system do
  # 画面の横幅が、ブラウザの幅を超えていない（横スクロールが出ない）
  def expect_no_horizontal_overflow(label)
    overflow = page.evaluate_script("document.documentElement.scrollWidth - window.innerWidth")

    expect(overflow).to be <= 0, "#{label} が横にはみ出しています（#{overflow}px）"
  end

  def open_screen(path)
    visit path
    expect(page).to have_css "h1"
    expect_no_horizontal_overflow(path)
  end

  before do
    page.current_window.resize_to(375, 812)
    Prosopite.pause { DemoData.load(today: Date.current) }
  end

  it "ログイン前の画面（C-01・C-03・E-01・E-02）" do
    open_screen new_user_session_path
    open_screen new_user_password_path
    open_screen "/404.html" # E-01（本番で表示される静的ページ）
    open_screen "/500.html" # E-02
    expect(page).to have_css "h1"
  end

  it "先生の全画面（T-01〜T-08）" do
    sign_in User.find_by!(email: "teacher@demo.example.com")

    paths = [ teacher_root_path, teacher_students_path, new_teacher_student_path, edit_teacher_student_path(Student.first),
      teacher_lesson_slots_path, new_teacher_lesson_slot_path, edit_teacher_lesson_slot_path(LessonSlot.first),
      teacher_makeup_slots_path, new_teacher_makeup_slot_path, edit_teacher_makeup_slot_path(MakeupSlot.upcoming.first),
      edit_teacher_makeup_rule_path ]
    paths.each { |path| open_screen(path) }
    expect(paths.size).to eq 11
  end

  it "保護者の全画面（P-01〜P-05）：欠席から振替の確定まで" do
    sign_in User.find_by!(email: "hanako@demo.example.com")

    open_screen root_path # P-01
    first(:link, "欠席する").click
    expect(page).to have_css "h1"
    expect_no_horizontal_overflow("P-02")
    first(:button, "この枠にする").click
    expect(page).to have_css "h1", text: "内容の確認"
    expect_no_horizontal_overflow("P-03")
    click_button "確定する"
    expect(page).to have_css "h1", text: "欠席を受け付けました"
    expect_no_horizontal_overflow("P-04")

    open_screen schedule_path # P-05
    first(:link, "振替を選ぶ").click
    expect(page).to have_css "h1", text: "振替の日を選ぶ"
    expect_no_horizontal_overflow("P-02（予定一覧から）")
  end
end
