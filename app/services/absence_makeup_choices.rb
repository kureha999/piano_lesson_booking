# 欠席を連絡するときの振替の選択肢（P-02・P-03）。まだ欠席を登録しない段階で、「振替権が付くか」「どの枠を選べるか」を調べる。
#
# 使い方：
#   choices = AbsenceMakeupChoices.new(student, absence)   # absence は、保存前でもよい（固定枠と欠席する日が必要）
#   choices.eligible?           # 振替権が付くか（付かないときは、振替枠を選べない）
#   choices.eligibility         # 判定（MakeupCreditEligibility。付かない理由など）
#   choices.expires_on          # 振替権の期限
#   choices.period              # 受講できる期間（欠席日の翌日〜期限）
#   choices.slots               # 予約できる振替枠（P-02）
#   choices.reason_counts       # 予約できる枠がないときの、理由ごとの枠の数（P-02）
#   choices.problem_with(slot)  # 選んだ枠で確定できない理由（P-03）。確定できるなら nil
#     :no_credit  振替権が付かなくなっている（P-02 を開いた後に、締切を過ぎたなど）
#     それ以外     枠を予約できない理由（MakeupSlotAvailability#unavailable_reason と同じ）
class AbsenceMakeupChoices
  attr_reader :eligibility

  def initialize(student, absence)
    @student = student
    @absence = absence
    @eligibility = MakeupCreditEligibility.new(absence)
  end

  def eligible?
    eligibility.eligible?
  end

  def expires_on
    eligibility.expires_on
  end

  def period
    (@absence.lesson_on + 1)..expires_on
  end

  def slots
    @slots ||= availability.slots
  end

  def reason_counts
    slots.empty? ? availability.unavailable_reason_counts : {}
  end

  def problem_with(slot)
    return :no_credit unless eligible?

    availability.unavailable_reason(slot)
  end

  private

  # まだ登録していない欠席に付く予定の振替権で、予約できる枠を調べる
  def availability
    @availability ||= MakeupSlotAvailability.new(MakeupCredit.new(student: @student, absence: @absence, expires_on: expires_on))
  end
end
