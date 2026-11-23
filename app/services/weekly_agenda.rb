# T-01 ダッシュボード（先生）に表示する、今週の欠席と振替予約（F-06、README 12-4）。
#
# 使い方：
#   agenda = WeeklyAgenda.new
#   agenda.week      # 今週（日本時間の月曜日〜日曜日）の日付の範囲
#   agenda.entries   # 今週の欠席と振替予約を、開始日時の順に並べた Entry の配列
#
# 今週の欠席：欠席するレッスンの日が今週のもの（もう終わった日も含む）。
#   締切後の欠席（振替権が付かない）は、Entry#same_day_absence? で「当日欠席」と区別できる。
# 今週の振替予約：振替枠が今週にある有効な予約（キャンセルした予約は含まない）。
class WeeklyAgenda
  # kind は :absence（欠席）か :makeup（振替予約）。absence・reservation は、どちらか一方が入る
  Entry = Data.define(:kind, :starts_at, :ends_at, :student, :guardian, :absence, :reservation) do
    def absence? = kind == :absence
    def makeup? = kind == :makeup

    # 締切後の欠席（当日欠席）。先生の一覧に「当日欠席」と表示する（README 12-2）
    def same_day_absence? = absence? && absence.after_deadline?

    # 月の上限を超えた欠席（振替権は付かない）
    def over_limit_absence? = absence? && absence.over_monthly_limit?

    # 欠席に付いた振替権で予約した、有効な振替予約（なければ nil）
    def makeup_reservation = absence&.makeup_credit&.active_reservation
  end

  def initialize(now: Time.current)
    @today = now.in_time_zone.to_date
  end

  # 今週。月曜日はじまり
  def week
    @week ||= @today.beginning_of_week(:monday)..@today.end_of_week(:monday)
  end

  def entries
    (absence_entries + makeup_entries).sort_by { |entry| [ entry.starts_at, entry.kind.to_s ] }
  end

  private

  def absence_entries
    Absence.where(lesson_on: week).includes(lesson_slot: { student: :guardian }, makeup_credit: { active_reservation: :makeup_slot }).map do |absence|
      slot = absence.lesson_slot
      starts_at = absence.lesson_starts_at
      ends_at = starts_at + (slot.end_time - slot.start_time)
      Entry.new(kind: :absence, starts_at: starts_at, ends_at: ends_at, student: slot.student, guardian: slot.student.guardian,
        absence: absence, reservation: nil)
    end
  end

  def makeup_entries
    period = week.begin.beginning_of_day..week.end.end_of_day
    MakeupReservation.active.joins(:makeup_slot).where(makeup_slots: { starts_at: period })
      .includes(:makeup_slot, student: :guardian, makeup_credit: :absence).map do |reservation|
      slot = reservation.makeup_slot
      Entry.new(kind: :makeup, starts_at: slot.starts_at, ends_at: slot.ends_at, student: reservation.student,
        guardian: reservation.student.guardian, absence: nil, reservation: reservation)
    end
  end
end
