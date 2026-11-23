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

  # 子どもが何人いても、クエリの数が増えないように、欠席・振替予約・振替権は、全員分をまとめて読み込む（N+1 を避ける）
  def summaries
    students = @students.includes(:lesson_slots).order(:id).to_a
    ids = students.map(&:id)
    absent_keys = absent_keys_by_student(ids)
    reservations = reservations_by_student(ids)
    unused_credits = unused_credits_by_student(ids)

    students.map do |student|
      entries = lesson_entries(student, absent_keys[student.id] || Set.new) + makeup_entries(reservations[student.id] || [])
      Summary.new(student: student, entries: entries.sort_by { |entry| [ entry.starts_at, entry.kind.to_s ] },
        unused_credits: unused_credits[student.id] || [])
    end
  end

  private

  def today
    @today ||= @now.in_time_zone.to_date
  end

  def lesson_entries(student, absent_keys)
    lessons = LessonSchedule.for(student, today..(today + PERIOD_DAYS - 1)).lessons.select { |lesson| lesson.starts_at > @now }
    lessons.map do |lesson|
      Entry.new(kind: :lesson, starts_at: lesson.starts_at, ends_at: lesson.ends_at, lesson: lesson,
        absent: absent_keys.include?(lesson.key), reservation: nil)
    end
  end

  # { 生徒の ID => 今日以降の欠席の (固定枠の ID, 日付) の Set }
  def absent_keys_by_student(student_ids)
    Absence.joins(:lesson_slot).where(lesson_slots: { student_id: student_ids }, lesson_on: today..)
      .pluck("lesson_slots.student_id", :lesson_slot_id, :lesson_on)
      .group_by(&:first).transform_values { |rows| rows.to_set { |_, slot_id, date| [ slot_id, date ] } }
  end

  # { 生徒の ID => これから受ける振替予約 }。終わった枠は含めない
  def reservations_by_student(student_ids)
    MakeupReservation.where(student_id: student_ids).active.joins(:makeup_slot).merge(MakeupSlot.where("makeup_slots.ends_at > ?", @now))
      .includes(:makeup_slot, makeup_credit: :absence).group_by(&:student_id)
  end

  # { 生徒の ID => 未使用の振替権（期限が近い順） }
  def unused_credits_by_student(student_ids)
    MakeupCredit.where(student_id: student_ids).unused(@now).includes(:absence).order(:expires_on, :id).group_by(&:student_id)
  end

  def makeup_entries(reservations)
    reservations.map do |reservation|
      slot = reservation.makeup_slot
      Entry.new(kind: :makeup, starts_at: slot.starts_at, ends_at: slot.ends_at, lesson: nil, absent: false, reservation: reservation)
    end
  end
end
