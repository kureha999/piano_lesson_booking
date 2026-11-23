require "rails_helper"

# 先生の登録・編集画面（生徒・固定枠・振替枠・振替ルール）の、全ルート（一覧・フォーム・登録・更新）に対する権限の確認。
# 各画面の spec で個別に確認している内容を、すべてのルートで漏れなく確認する。
RSpec.describe "先生の画面の権限（全ルート）", type: :request do
  # 保護者のときは、自分の子どもの行を使う（ほかの家庭の行は、権限の前に 404 になる。各画面の spec で確認ずみ）
  let(:guardian) { create(:guardian) }
  let!(:student) { create(:student, guardian: guardian) }
  let!(:lesson_slot) { create(:lesson_slot, student: student) }
  let!(:makeup_slot) { create(:makeup_slot, starts_at: 3.days.from_now.change(hour: 10), ends_at: 3.days.from_now.change(hour: 10, min: 30)) }

  # [ HTTP メソッド, パス, 登録・更新の送信内容 ]。パスは、ここで作った行の ID を使う
  def routes
    [
      [ :get, teacher_students_path ],
      [ :get, new_teacher_student_path ],
      [ :post, teacher_students_path, { student: { name: "あおい", guardian_name: "山田花子", guardian_email: "new@example.com" } } ],
      [ :get, edit_teacher_student_path(student) ],
      [ :patch, teacher_student_path(student), { student: { name: "変更後" } } ],
      [ :get, teacher_lesson_slots_path ],
      [ :get, new_teacher_lesson_slot_path ],
      [ :post, teacher_lesson_slots_path, { lesson_slot: { student_id: student.id, wday: 5, start_time: "17:00", end_time: "17:30" } } ],
      [ :get, edit_teacher_lesson_slot_path(lesson_slot) ],
      [ :patch, teacher_lesson_slot_path(lesson_slot), { lesson_slot: { wday: 6 } } ],
      [ :get, teacher_makeup_slots_path ],
      [ :get, new_teacher_makeup_slot_path ],
      [ :post, teacher_makeup_slots_path, { makeup_slot: { capacity: 1 } } ],
      [ :get, edit_teacher_makeup_slot_path(makeup_slot) ],
      [ :patch, teacher_makeup_slot_path(makeup_slot), { makeup_slot: { capacity: 3 } } ],
      [ :get, edit_teacher_makeup_rule_path ],
      [ :patch, teacher_makeup_rule_path, { makeup_rule: { monthly_limit: "5" } } ]
    ]
  end

  def snapshot
    [ User.count, Student.count, student.reload.name, LessonSlot.count, lesson_slot.reload.wday,
      MakeupSlot.count, makeup_slot.reload.capacity, MakeupRule.count ]
  end

  # すべてのルートを順に開き、返ってきた状態（リダイレクト先か 404）を [ メソッド パス 状態 ] で返す
  def request_all
    routes.map do |method, path, params|
      new_scan("#{method.upcase} #{path}") # ルートごとに別の scan にする
      public_send(method, path, params: params)
      outcome = response.redirect? ? response.location.delete_prefix("http://www.example.com") : response.status
      "#{method.upcase} #{path} → #{outcome}"
    end
  end

  context "保護者のとき" do
    before { sign_in guardian }

    it "すべてのルートで P-01 に戻す（振替枠の編集・更新だけは、保護者に見せない 404）。何も登録・更新しない" do
      before_state = snapshot

      outcomes = request_all

      expect(outcomes).to all(match(/→ (\/|404)\z/))
      expect(outcomes.count { |outcome| outcome.end_with?("→ /") }).to eq 15
      expect(outcomes.grep(/makeup_slots\/\d+/)).to all(end_with("→ 404")) # 編集・更新の2ルート
      expect(snapshot).to eq before_state
    end
  end

  context "ログインしていないとき" do
    it "すべてのルートで C-01 に移動し、何も登録・更新しない" do
      before_state = snapshot

      outcomes = request_all

      expect(outcomes).to all(end_with("→ /login"))
      expect(snapshot).to eq before_state
    end
  end
end
