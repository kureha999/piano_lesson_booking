# 欠席・振替のメール（F-12、README 8・12-5②）。先生と保護者の両方に送る（送り分けは MakeupNotifications）。
# 送るのは Active Job（deliver_later）。本文は、送る時点のデータから作る。
#   absence_received：欠席受付（振替を予約したときは、振替確定も同じメールで伝える）
#   makeup_confirmed：振替確定（未使用の振替権から、あとで振替枠を予約したとき）
#   makeup_canceled ：振替予約のキャンセル
class MakeupMailer < ApplicationMailer
  helper :application, :absences

  def absence_received(absence, recipient)
    @absence = absence
    @recipient = recipient
    setup_lesson(absence.lesson_slot.student)
    @credit = absence.makeup_credit
    @reservation = @credit&.active_reservation
    @rule = MakeupRule.current

    mail(to: recipient.email, subject: "【ふりかえ帳】#{@student.name}さんの欠席を受け付けました（#{lesson_date(absence.lesson_on)}）")
  end

  def makeup_confirmed(reservation, recipient)
    setup_reservation(reservation, recipient)

    mail(to: recipient.email, subject: "【ふりかえ帳】#{@student.name}さんの振替が確定しました（#{lesson_date(@reservation.makeup_slot.starts_at.to_date)}）")
  end

  def makeup_canceled(reservation, recipient)
    setup_reservation(reservation, recipient)

    mail(to: recipient.email, subject: "【ふりかえ帳】#{@student.name}さんの振替予約をキャンセルしました（#{lesson_date(@reservation.makeup_slot.starts_at.to_date)}）")
  end

  private

  def setup_lesson(student)
    @student = student
    @guardian = student.guardian
  end

  def setup_reservation(reservation, recipient)
    @reservation = reservation
    @recipient = recipient
    @credit = reservation.makeup_credit
    @absence = @credit.absence
    setup_lesson(reservation.student)
  end

  # 件名用の「11月11日（水）」
  def lesson_date(date)
    "#{date.strftime('%-m月%-d日')}（#{I18n.t('date.abbr_day_names')[date.wday]}）"
  end
end
