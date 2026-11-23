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

  # T-03 生徒を登録したあとのメッセージ（redirect_to に渡す flash）。form は StudentForm（保存ずみ）。
  # 新しい保護者には招待メールを送るので、送れたかどうかも伝える
  def student_created_flash(form)
    return { notice: "登録済みの保護者（#{form.guardian.name}さん）に、#{form.name}さんを追加しました。" } unless form.guardian_created?

    message = "#{form.name}さんと保護者（#{form.guardian.name}さん）を登録しました。"
    if form.invitation_sent?
      { notice: "#{message}#{form.guardian.email} に、パスワード設定の招待メールを送りました。" }
    else
      { notice: message, alert: "招待メールを送れませんでした。保護者の方に、ログイン画面の「パスワードを忘れた方」からパスワードを設定してもらってください。" }
    end
  end

  # T-05 固定枠を変更したあとのメッセージ。form は LessonSlotForm（保存ずみ）、slot は変更前の固定枠
  def lesson_slot_updated_message(form, slot)
    name = slot.student.name
    return "#{name}さんの固定枠は、変更がありませんでした。" if form.unchanged?

    "#{name}さんの固定枠を変更しました。今の枠は前日で終了し、#{japanese_date(form.lesson_slot.starts_on)}から新しい枠になります。"
  end
end
