# 指定した日が属する月（日本時間の1日〜末日）に、振替権が付いた欠席の数（= 今月の振替の利用回数。README 12-2・12-6）。
# 月の上限の判定（MakeupCreditEligibility）、T-02 の利用回数、P-01 の残り回数で使う。保存せずに、欠席から数える。
#
# 使い方：
#   MonthlyCreditUsage.count(student, date)                  # 生徒1人の数
#   MonthlyCreditUsage.counts(date)                          # { 生徒の ID => 数 }（欠席がない生徒は含まない）
#   MonthlyCreditUsage.counts(date, student_ids: [ 1, 2 ])   # 指定した生徒だけ
class MonthlyCreditUsage
  def self.count(student, date)
    counts(date, student_ids: [ student.id ]).fetch(student.id, 0)
  end

  def self.counts(date, student_ids: nil)
    absences = Absence.joins(:lesson_slot).where(no_credit_reason: nil, lesson_on: date.all_month)
    absences = absences.where(lesson_slots: { student_id: student_ids }) if student_ids
    absences.group("lesson_slots.student_id").count
  end
end
