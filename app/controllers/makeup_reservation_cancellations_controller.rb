# 振替予約のキャンセル（P-05 の「キャンセル」。README 12-5②）。締切前の予約だけをキャンセルできる。
# 確認ダイアログ（D-01）は、画面のボタンで出す。締切後のリクエストは、ここ（CancelMakeupReservation）でも拒否する。
class MakeupReservationCancellationsController < ApplicationController
  before_action { authorize :makeup_reservation, :cancel? } # 保護者だけ

  def create
    # 自分の子どもの予約だけ。ほかの家庭の予約は RecordNotFound（E-01：404）になる
    student = policy_scope(Student).find(params[:student_id])
    reservation = student.makeup_reservations.includes(:makeup_slot).find(params[:makeup_reservation_id])

    result = CancelMakeupReservation.call(reservation)
    if result.success?
      MakeupNotifications.makeup_canceled(reservation) # キャンセルした後に、先生と保護者へメールを送る
      redirect_to schedule_path, notice: "#{helpers.makeup_slot_text(reservation.makeup_slot)}の振替予約をキャンセルしました。振替権は、また使えます。"
    else
      redirect_to schedule_path, alert: failure_message(result.reason, reservation)
    end
  end

  private

  def failure_message(reason, reservation)
    case reason
    when :already_canceled
      "この振替予約は、すでにキャンセルされています。"
    else
      deadline = reservation.makeup_slot.reservation_deadline
      "キャンセルの締切（#{deadline.strftime('%-m月%-d日 %H:%M')}）を過ぎているため、キャンセルできません。先生にご連絡ください。"
    end
  end
end
