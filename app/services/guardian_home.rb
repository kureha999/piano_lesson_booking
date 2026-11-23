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

  # 子どもが何人いても、クエリの数が増えないように、欠席・振替権は、全員分をまとめて読み込む（N+1 を避ける）
  def summaries
    students = @students.includes(:lesson_slots).order(:id).to_a
    ids = students.map(&:id)
    credited_counts = MonthlyCreditUsage.counts(today, student_ids: ids)
    absent_keys = absent_keys_by_student(ids)
    unused_credits = unused_credits_by_student(ids)

    students.map { |student| summary_of(student, credited_counts.fetch(student.id, 0), absent_keys[student.id] || Set.new, unused_credits[student.id] || []) }
  end

  private

  def today
    @today ||= @now.in_time_zone.to_date
  end

  def summary_of(student, credited, absent_keys, unused_credits)
    Summary.new(
      student: student,
      lesson_items: lesson_items_of(student, absent_keys),
      remaining_count: [ @rule.monthly_limit - credited, 0 ].max,
      monthly_limit: @rule.monthly_limit,
      unused_credits: unused_credits
    )
  end

  def lesson_items_of(student, absent_keys)
    lessons = LessonSchedule.for(student, today..(today + PERIOD_DAYS - 1)).lessons.select { |lesson| lesson.starts_at > @now }
    lessons.map { |lesson| LessonItem.new(lesson: lesson, absent: absent_keys.include?(lesson.key)) }
  end

  # { 生徒の ID => 今日以降の欠席の (固定枠の ID, 日付) の Set }
  def absent_keys_by_student(student_ids)
    Absence.joins(:lesson_slot).where(lesson_slots: { student_id: student_ids }, lesson_on: today..)
      .pluck("lesson_slots.student_id", :lesson_slot_id, :lesson_on)
      .group_by(&:first).transform_values { |rows| rows.to_set { |_, slot_id, date| [ slot_id, date ] } }
  end

  # { 生徒の ID => 未使用の振替権（期限が近い順） }
  def unused_credits_by_student(student_ids)
    MakeupCredit.where(student_id: student_ids).unused(@now).includes(:absence).order(:expires_on, :id).group_by(&:student_id)
  end
end
