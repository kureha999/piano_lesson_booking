# 欠席を登録し、振替権を付けるかどうかを判定する（F-08・F-11、README 12-2）。
#
# 使い方：
#   result = RegisterAbsence.call(lesson_slot: slot, lesson_on: Date.new(2026, 11, 11), reported_by: user)
#   result.success?        # 欠席を登録できたか
#   result.absence         # 登録した欠席（失敗したときは、エラーが入った未保存の欠席）
#   result.makeup_credit   # 付けた振替権（付かなかったときは nil。理由は absence.no_credit_reason）
#
# 振替権が付く条件（締切の判定を先に行う）：
#   1. 欠席連絡の締切（レッスン開始の○時間前）までに連絡した。締切ちょうどの時刻までは付く
#   2. 欠席日が属する月（日本時間の1日〜末日）に、その生徒に振替権が付いた欠席が、月の上限に達していない
# 付かない場合も、欠席は登録する。理由は、1 に当てはまらなければ「締切後」、2 に当てはまらなければ「月の上限」。
# 締切後の欠席は振替権が付かないので、月の上限の回数には数えない。
#
# 振替の期限（expires_on）は、作成時のルールで「欠席日 ＋ 期限の日数」として計算し、保存する。
# 後からルールを変えても、すでにある振替権は変わらない。
#
# 同時に連絡しても月の上限を超えないよう、生徒の行をロックしてから数える（README 12-6）。
class RegisterAbsence
  Result = Struct.new(:absence, :makeup_credit) do
    def success? = absence.persisted?
  end

  def self.call(...) = new(...).call

  def initialize(lesson_slot:, lesson_on:, reported_by:)
    @lesson_slot = lesson_slot
    @lesson_on = lesson_on
    @reported_by = reported_by
  end

  def call
    absence = Absence.new(lesson_slot: @lesson_slot, lesson_on: @lesson_on, reported_by: @reported_by)
    credit = nil

    student.with_lock do
      if absence.valid?
        rule = MakeupRule.current
        absence.no_credit_reason = no_credit_reason(absence, rule)
        absence.save!
        credit = grant_credit(absence, rule) unless absence.no_credit_reason
      end
    end

    Result.new(absence, credit)
  rescue ActiveRecord::RecordNotUnique
    # 検証の後に、同じレッスンの欠席が登録された場合（DB の一意インデックスが止める）
    absence.errors.add(:lesson_on, "のレッスンは、すでに欠席を連絡しています")
    Result.new(absence, nil)
  end

  private

  def student
    @lesson_slot.student
  end

  # 振替権が付かない理由。付くときは nil
  def no_credit_reason(absence, rule)
    return :after_deadline if Time.current > absence.lesson_starts_at - rule.absence_deadline_hours.hours
    return :over_monthly_limit if student.credited_absence_count_in_month(absence.lesson_on) >= rule.monthly_limit

    nil
  end

  def grant_credit(absence, rule)
    MakeupCredit.create!(student: student, absence: absence, expires_on: absence.lesson_on + rule.valid_days)
  end
end
