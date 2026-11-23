# 未使用の振替権から、振替枠を選んで予約する（P-05 の「振替を選ぶ」から始まる流れ。README 12-5②）。
#   P-02 振替枠の選択（new）→ P-03 確認（confirm）→ P-03 の「確定する」（create）→ P-04 完了（show）
# 欠席する流れ（AbsencesController）と違い、欠席はすでに登録ずみで、振替予約だけを作る。
class MakeupReservationsController < ApplicationController
  include MakeupSlotAlerts

  before_action { authorize :makeup_reservation } # 保護者だけ（先生は、ホームに戻される）
  before_action :set_student
  before_action :set_credit
  before_action :require_usable_credit, only: %i[new confirm create]
  before_action :set_makeup_slot, only: %i[confirm create]

  # P-02 振替枠の選択
  def new
    availability = MakeupSlotAvailability.new(@credit)
    @slots = availability.slots
    @reason_counts = @slots.empty? ? availability.unavailable_reason_counts : {}
    @period = (@credit.absence.lesson_on + 1)..@credit.expires_on
  end

  # P-03 確認
  def confirm
    reason = MakeupSlotAvailability.new(@credit).unavailable_reason(@makeup_slot)
    redirect_to new_student_makeup_credit_makeup_reservation_path(@student, @credit), alert: slot_alert(reason) if reason
  end

  # P-03 の「確定する」
  def create
    result = ReserveMakeupSlot.call(makeup_credit: @credit, makeup_slot: @makeup_slot)
    return redirect_to student_makeup_credit_makeup_reservation_path(@student, @credit, result.reservation) if result.success?
    return redirect_to schedule_path, alert: "この振替権は、すでに予約に使われています。" if result.reason == :credit_used

    redirect_to new_student_makeup_credit_makeup_reservation_path(@student, @credit), alert: slot_alert(result.reason)
  end

  # P-04 完了
  def show
    @reservation = @credit.makeup_reservations.find(params[:id])
  end

  private

  # 自分の子どもだけ。ほかの家庭の子どもは RecordNotFound（E-01：404）になる
  def set_student
    @student = policy_scope(Student).find(params[:student_id])
  end

  def set_credit
    @credit = @student.makeup_credits.includes(:absence).find(params[:makeup_credit_id])
  end

  # 予約に使えるのは、未使用の振替権だけ（期限切れ・予約ずみ・使用ずみは、予定一覧に戻す）
  def require_usable_credit
    case @credit.status
    when :unused then nil
    when :expired then redirect_to schedule_path, alert: "この振替権は、期限（#{helpers.japanese_date(@credit.expires_on)}）を過ぎています。"
    else redirect_to schedule_path, alert: "この振替権は、すでに予約に使われています。"
    end
  end

  # 選んだ振替枠。存在しない枠を指定されたら、選び直してもらう
  def set_makeup_slot
    @makeup_slot = MakeupSlot.find_by(id: params[:makeup_slot_id])
    return if @makeup_slot

    redirect_to new_student_makeup_credit_makeup_reservation_path(@student, @credit), alert: slot_alert(:not_found)
  end
end
