# 欠席に振替権が付くかどうかの判定（README 12-2）。RegisterAbsence（登録するとき）と、
# P-02・P-03（登録する前に、振替を選べるか・振替権が付かない理由を表示する）で同じ判定を使う。
#
# 使い方：
#   eligibility = MakeupCreditEligibility.new(absence)   # absence は、保存前でもよい（固定枠と欠席する日が必要）
#   eligibility.eligible?         # 振替権が付くか
#   eligibility.no_credit_reason  # 付かない理由（:after_deadline か :over_monthly_limit）。付くときは nil
#   eligibility.expires_on        # 振替権の期限（欠席日 ＋ 期限の日数）
#
# 判定の順序と、締切・月の上限の数え方は RegisterAbsence の説明のとおり。
# 同時に連絡しても上限を超えないようにするロックは、保存する側（RegisterAbsence）が行う。
class MakeupCreditEligibility
  def initialize(absence, now: Time.current, rule: MakeupRule.current)
    @absence = absence
    @now = now
    @rule = rule
  end

  def eligible?
    no_credit_reason.nil?
  end

  def no_credit_reason
    return :after_deadline if @now > @absence.lesson_starts_at - @rule.absence_deadline_hours.hours
    return :over_monthly_limit if student.credited_absence_count_in_month(@absence.lesson_on) >= @rule.monthly_limit

    nil
  end

  def expires_on
    @absence.lesson_on + @rule.valid_days
  end

  private

  def student
    @absence.lesson_slot.student
  end
end
