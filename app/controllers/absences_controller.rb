# 保護者の欠席連絡（P-01 のレッスンの「欠席する」から始まる流れ。README 12-5②）。
#   P-02 振替枠の選択（new）：ルールの範囲内で予約できる枠だけを表示する
#   P-03 確認・P-04 完了：#47
# まだ欠席は登録しない（P-03 の「確定する」で、欠席連絡と振替の予約をまとめて確定する）。
class AbsencesController < ApplicationController
  before_action { authorize :absence } # 保護者だけ（先生は、ホームに戻される）
  before_action :set_student
  before_action :set_lesson, only: :new

  # P-02 振替枠の選択
  def new
    eligibility = MakeupCreditEligibility.new(@absence)
    # 振替権が付かない欠席（締切後・月の上限を超えた）は、振替枠を選べないので P-02 を飛ばして P-03 に進む
    return redirect_to confirm_student_absences_path(@student, lesson_params) unless eligibility.eligible?

    credit = MakeupCredit.new(student: @student, absence: @absence, expires_on: eligibility.expires_on)
    @availability = MakeupSlotAvailability.new(credit)
    @slots = @availability.slots
    @expires_on = eligibility.expires_on
    @reason_counts = @slots.empty? ? @availability.unavailable_reason_counts : {}
  end

  private

  # 自分の子どもだけ。ほかの家庭の子どもは RecordNotFound（E-01：404）になる
  def set_student
    @student = policy_scope(Student).find(params[:student_id])
  end

  # 欠席するレッスン（その子どもの固定枠と日付）。欠席できないレッスン（曜日が違う・もう始まった・欠席ずみ）は、ホームに戻す
  def set_lesson
    lesson_slot = @student.lesson_slots.find(params[:lesson_slot_id])
    @absence = Absence.new(lesson_slot: lesson_slot, lesson_on: parse_date(params[:lesson_on]), reported_by: current_user)
    return if @absence.valid?

    redirect_to root_path, alert: "このレッスンは欠席を連絡できません。#{@absence.errors.full_messages.to_sentence}"
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
