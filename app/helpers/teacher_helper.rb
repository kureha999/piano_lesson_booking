module TeacherHelper
  # 初期設定の各手順（SetupProgress::Step#key）の画面
  def setup_step_path(key)
    {
      student: new_teacher_student_path,           # T-03 生徒の登録
      lesson_slot: new_teacher_lesson_slot_path,   # T-05 固定枠の登録
      makeup_slot: new_teacher_makeup_slot_path,   # T-07 振替枠の登録
      makeup_rule: edit_teacher_makeup_rule_path   # T-08 振替ルールの設定
    }.fetch(key)
  end
end
