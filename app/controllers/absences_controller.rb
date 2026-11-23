# 保護者の欠席連絡（P-01 のレッスンの「欠席する」から始まる流れ。README 12-5②）。
#   P-02 振替枠の選択（new）：ルールの範囲内で予約できる枠だけを表示する
#   P-03 確認（confirm）：確定する内容を表示する。振替権が付かない場合は、その理由も表示する
#   P-03 の「確定する」（create）：欠席・振替権・振替予約を1つのトランザクションで作る。失敗したら、何も登録せずに戻す
#   P-04 完了（show）
# P-02 と P-03 では、まだ欠席を登録しない。どのレッスンか・どの枠を選んだかは、URL のパラメーターで渡す。
class AbsencesController < ApplicationController
  include MakeupSlotAlerts
  include OwnStudent

  before_action { authorize :absence } # 保護者だけ（先生は、ホームに戻される）
  before_action :set_student
  before_action :set_lesson, only: %i[new confirm create]
  before_action :set_makeup_slot, only: %i[confirm create]

  # P-02 振替枠の選択
  def new
    @choices = AbsenceMakeupChoices.new(@student, @absence)
    # 振替権が付かない欠席（締切後・月の上限を超えた）は、振替枠を選べないので P-02 を飛ばして P-03 に進む
    redirect_to confirm_student_absences_path(@student, lesson_params) unless @choices.eligible?
  end

  # P-03 確認
  def confirm
    @choices = AbsenceMakeupChoices.new(@student, @absence)
    return unless @makeup_slot

    # 枠を選んだのに、振替権が付かない（P-02 を開いた後に締切を過ぎた）・枠が予約できなくなった場合は、選び直してもらう
    problem = @choices.problem_with(@makeup_slot)
    redirect_after_problem(problem) if problem
  end

  # P-03 の「確定する」
  def create
    result = ConfirmAbsence.call(lesson_slot: @absence.lesson_slot, lesson_on: @absence.lesson_on,
      reported_by: current_user, makeup_slot: @makeup_slot)
    return redirect_after_problem(result.reason) unless result.success?

    MakeupNotifications.absence_received(result.absence) # 確定した後に、先生と保護者へメールを送る
    redirect_to student_absence_path(@student, result.absence)
  end

  # P-04 完了
  def show
    @absence = Absence.joins(:lesson_slot).where(lesson_slots: { student_id: @student.id }).find(params[:id])
    @makeup_credit = @absence.makeup_credit
    @reservation = @makeup_credit&.active_reservation
    @rule = MakeupRule.current
  end

  private

  # 欠席するレッスン（その子どもの固定枠と日付）。欠席できないレッスン（曜日が違う・もう始まった・欠席ずみ）は、ホームに戻す
  def set_lesson
    lesson_slot = @student.lesson_slots.find(params[:lesson_slot_id])
    @absence = Absence.new(lesson_slot: lesson_slot, lesson_on: parse_date(params[:lesson_on]), reported_by: current_user)
    return if @absence.valid?

    redirect_to root_path, alert: "このレッスンは欠席を連絡できません。#{@absence.errors.full_messages.to_sentence}"
  end

  # 選んだ振替枠。「振替は後で選ぶ」のときは指定しない。存在しない枠を指定されたら、選び直してもらう
  def set_makeup_slot
    return if params[:makeup_slot_id].blank?

    @makeup_slot = MakeupSlot.find_by(id: params[:makeup_slot_id])
    redirect_to new_student_absence_path(@student, lesson_params), alert: slot_alert(:not_found) unless @makeup_slot
  end

  # 確定できない理由（AbsenceMakeupChoices#problem_with・ConfirmAbsence の reason）に合わせて、戻す画面を決める
  def redirect_after_problem(reason)
    case reason
    when :invalid
      redirect_to root_path, alert: "このレッスンは欠席を連絡できません。"
    when :no_credit
      redirect_to confirm_student_absences_path(@student, lesson_params), alert: no_credit_alert
    else
      redirect_to new_student_absence_path(@student, lesson_params), alert: slot_alert(reason)
    end
  end

  def no_credit_alert
    "振替権が付かなくなったため、振替枠は選べません。欠席だけを連絡する場合は、このまま確定してください。"
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end

  def lesson_params
    { lesson_slot_id: @absence.lesson_slot_id, lesson_on: @absence.lesson_on }
  end
end
