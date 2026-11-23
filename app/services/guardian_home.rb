# P-01 ホーム（保護者）に表示する内容を、子どもごとにまとめる（F-07、README 12-4）。
#
# 使い方：
#   GuardianHome.new(policy_scope(Student)).summaries   # 子ども（兄弟を含む）ごとの Summary の配列
#
# 子どもごとに、次の3つを表示する。
#   - 今後2週間のレッスン（今日から14日間のうち、まだ始まっていないもの）。欠席連絡ずみのレッスンには absent が付く
#   - 今月の振替の残り回数（月の上限 − 今月（欠席日が属する月）に振替権が付いた欠席の数。保存せずに計算する。0 より小さくならない）
#   - 未使用の振替権（期限が近い順。期限つき）
class GuardianHome
  PERIOD_DAYS = 14

  # 1人分。lesson_items は LessonItem の配列
  Summary = Data.define(:student, :lesson_items, :remaining_count, :monthly_limit, :unused_credits)
  # 1回分のレッスン。lesson は LessonSchedule::Lesson、absent は欠席連絡ずみか
  LessonItem = Data.define(:lesson, :absent)

  def initialize(students, now: Time.current)
    @students = students
    @now = now
    @rule = MakeupRule.current
  end

  def summaries
    @students.includes(:lesson_slots).order(:id).map { |student| summary_of(student) }
  end

  private

  def today
    @today ||= @now.in_time_zone.to_date
  end

  def summary_of(student)
    credited = student.credited_absence_count_in_month(today)
    Summary.new(
      student: student,
      lesson_items: lesson_items_of(student),
      remaining_count: [ @rule.monthly_limit - credited, 0 ].max,
      monthly_limit: @rule.monthly_limit,
      unused_credits: student.makeup_credits.unused(@now).includes(:absence).order(:expires_on, :id).to_a
    )
  end

  def lesson_items_of(student)
    lessons = LessonSchedule.for(student, today..(today + PERIOD_DAYS - 1)).lessons.select { |lesson| lesson.starts_at > @now }
    absent_keys = student.absences.where(lesson_on: today..).pluck(:lesson_slot_id, :lesson_on).to_set
    lessons.map { |lesson| LessonItem.new(lesson: lesson, absent: absent_keys.include?(lesson.key)) }
  end
end
