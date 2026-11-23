# P-05 予定一覧（保護者）に表示する内容を、子どもごとにまとめる（F-07、README 12-4）。
#
# 使い方：
#   GuardianSchedule.new(policy_scope(Student)).summaries   # 子ども（兄弟を含む）ごとの Summary の配列
#
# 子どもごとに、次の2つを表示する。
#   - 今後8週間の固定レッスンと、これから受ける振替予約（有効な予約）を、開始日時の順に並べたもの
#   - 未使用の振替権（期限が近い順。ここから「振替を選ぶ」で、振替枠を予約できる）
class GuardianSchedule
  PERIOD_DAYS = 56

  Summary = Data.define(:student, :entries, :unused_credits)
  # 1件の予定。kind は :lesson（固定レッスン）か :makeup（振替）。
  #   lesson：固定レッスンのとき LessonSchedule::Lesson。absent は欠席連絡ずみか
  #   reservation：振替のとき MakeupReservation
  Entry = Data.define(:kind, :starts_at, :ends_at, :lesson, :absent, :reservation) do
    def lesson? = kind == :lesson
    def makeup? = kind == :makeup
  end

  def initialize(students, now: Time.current)
    @students = students
    @now = now
  end

  def summaries
    @students.includes(:lesson_slots).order(:id).map do |student|
      Summary.new(
        student: student,
        entries: (lesson_entries(student) + makeup_entries(student)).sort_by { |entry| [ entry.starts_at, entry.kind.to_s ] },
        unused_credits: student.makeup_credits.unused(@now).includes(:absence).order(:expires_on, :id).to_a
      )
    end
  end

  private

  def today
    @today ||= @now.in_time_zone.to_date
  end

  def lesson_entries(student)
    lessons = LessonSchedule.for(student, today..(today + PERIOD_DAYS - 1)).lessons.select { |lesson| lesson.starts_at > @now }
    absent_keys = student.absences.where(lesson_on: today..).pluck(:lesson_slot_id, :lesson_on).to_set
    lessons.map do |lesson|
      Entry.new(kind: :lesson, starts_at: lesson.starts_at, ends_at: lesson.ends_at, lesson: lesson,
        absent: absent_keys.include?(lesson.key), reservation: nil)
    end
  end

  # これから受ける振替予約。終わった枠は含めない
  def makeup_entries(student)
    student.makeup_reservations.active.joins(:makeup_slot).merge(MakeupSlot.where("makeup_slots.ends_at > ?", @now))
      .includes(:makeup_slot, makeup_credit: :absence).map do |reservation|
      slot = reservation.makeup_slot
      Entry.new(kind: :makeup, starts_at: slot.starts_at, ends_at: slot.ends_at, lesson: nil, absent: false, reservation: reservation)
    end
  end
end
