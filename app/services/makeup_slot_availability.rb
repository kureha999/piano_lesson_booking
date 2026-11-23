# 振替権ごとに、ルールの範囲内で予約できる振替枠を調べる（F-09・F-11、README 12-2）。
#
# 使い方：
#   availability = MakeupSlotAvailability.new(makeup_credit)
#   availability.slots                      # 予約できる振替枠（開始日時の順）
#   availability.unavailable_reason(slot)   # 予約できない理由（予約できるなら nil）
#
# 予約できない理由（上から順に判定し、最初に当てはまったものを返す）：
#   :credit_used      その振替権には、すでに有効な予約がある（再振替はできない）
#   :already_started  枠の開始日時を過ぎている
#   :out_of_period    受講日が、欠席日の翌日〜振替権の期限（expires_on）の間ではない（予約した日ではなく、受講する日で判定する）
#   :deadline_passed  振替予約の締切を過ぎている（枠の○日前の23:59まで。初期値は前日）
#   :full             定員に達している（キャンセルした予約は数えない）
#   :conflict         その生徒の固定レッスン、またはほかの有効な振替予約と、時間が重なる
#                     （欠席するレッスンは、重なりに数えない）
#
# 期限（expires_on）と締切は、日本時間の日付・時刻で判定する。締切のルールは、いまのルール（MakeupRule）を使う。
class MakeupSlotAvailability
  def initialize(makeup_credit, now: Time.current)
    @credit = makeup_credit
    @now = now
    @rule = MakeupRule.current
  end

  # 予約できる振替枠。まだ終わっていない枠だけを調べる
  def slots
    MakeupSlot.upcoming.select { |slot| unavailable_reason(slot).nil? }
  end

  def unavailable_reason(slot)
    return :credit_used if credit_used?
    return :already_started if slot.starts_at <= @now
    return :out_of_period unless period.cover?(slot.starts_at.to_date)
    return :deadline_passed if @now > reservation_deadline(slot)
    return :full if reserved_count(slot) >= slot.capacity
    return :conflict if conflicting?(slot)

    nil
  end

  private

  def student
    @credit.student
  end

  # 受講できる日。欠席日の翌日から、振替権の期限まで（両端を含む）
  def period
    @period ||= (@credit.absence.lesson_on + 1)..@credit.expires_on
  end

  # 振替予約の締切。枠の開始日の○日前の 23:59（日本時間）まで
  def reservation_deadline(slot)
    (slot.starts_at.to_date - @rule.reservation_deadline_days).end_of_day
  end

  def credit_used?
    return @credit_used if defined?(@credit_used)

    @credit_used = @credit.makeup_reservations.active.exists?
  end

  def reserved_count(slot)
    MakeupReservation.active.where(makeup_slot_id: slot.id).count
  end

  def conflicting?(slot)
    lesson_conflict?(slot) || reservation_conflict?(slot)
  end

  def lesson_conflict?(slot)
    lessons_near(slot).any? { |lesson| overlap?(lesson.starts_at, lesson.ends_at, slot) }
  end

  # その日の固定レッスン。欠席するレッスンは、受けないので除く
  def lessons_near(slot)
    dates = slot.starts_at.to_date..slot.ends_at.to_date
    LessonSchedule.for(student, dates).lessons.reject { |lesson| absent_keys.include?(lesson.key) }
  end

  def absent_keys
    @absent_keys ||= Absence.joins(:lesson_slot)
      .where(lesson_slots: { student_id: student.id })
      .pluck(:lesson_slot_id, :lesson_on).to_set
  end

  # ほかの有効な振替予約（この振替権の予約は、credit_used? で除いているので含まない）
  def reservation_conflict?(slot)
    student.makeup_reservations.active.includes(:makeup_slot).any? do |reservation|
      reservation.makeup_slot_id != slot.id && overlap?(reservation.makeup_slot.starts_at, reservation.makeup_slot.ends_at, slot)
    end
  end

  # 接しているだけ（終了と開始が同じ）は、重ならない
  def overlap?(starts_at, ends_at, slot)
    starts_at < slot.ends_at && ends_at > slot.starts_at
  end
end
