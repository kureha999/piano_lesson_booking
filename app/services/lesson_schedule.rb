# 固定枠から、指定した期間の各回のレッスン（日付・開始日時・終了日時）を計算する。
# 各回は保存しない（README 12-6「設計の方針」）。保存するのは、欠席などの例外だけ。
#
# 使い方：
#   LessonSchedule.for(student, Date.current..(Date.current + 13)).lessons   # 生徒の、今日から2週間分
#   LessonSchedule.new(LessonSlot.all, from..to).lessons                      # 渡した固定枠すべての各回
#
# 各回の適用期間は、固定枠の適用開始日〜適用終了日（両端を含む）。期間の外の日付は含めない。
# 欠席と組み合わせるときは、Lesson#key（固定枠の ID と、レッスンの日付）を、欠席の
# (lesson_slot_id, lesson_on) と照合する（absences の一意インデックスと同じ組み合わせ）。
#   absent_keys = Absence.where(...).pluck(:lesson_slot_id, :lesson_on).to_set
#   lessons.map { |lesson| [ lesson, absent_keys.include?(lesson.key) ] }
class LessonSchedule
  # 1回分のレッスン。lesson_slot は、元になった固定枠
  Lesson = Data.define(:lesson_slot, :date, :starts_at, :ends_at) do
    # 欠席（lesson_slot_id と lesson_on の組み合わせ）と照合するためのキー
    def key
      [ lesson_slot.id, date ]
    end

    def student
      lesson_slot.student
    end
  end

  # 生徒の固定枠から計算する
  def self.for(student, period)
    new(student.lesson_slots, period)
  end

  # slots：固定枠（LessonSlot の配列か、リレーション）。period：日付の範囲（Date の Range。終わりは含む）
  def initialize(slots, period)
    @slots = slots
    @period = period
  end

  # 期間内の各回を、開始日時の順に返す（同じ時刻なら、固定枠の ID 順）
  def lessons
    @slots.flat_map { |slot| lessons_of(slot) }.sort_by { |lesson| [ lesson.starts_at, lesson.lesson_slot.id ] }
  end

  private

  def lessons_of(slot)
    from = [ @period.begin, slot.starts_on ].max
    to = [ @period.end, slot.ends_on ].compact.min
    return [] if from > to

    first = from + ((slot.wday - from.wday) % 7) # from 以降で、最初の、固定枠の曜日の日
    first.step(to, 7).map { |date| build_lesson(slot, date) }
  end

  # 時刻（time 型の列はタイムゾーンを変換しない）は、日本時間のその日の時刻として扱う
  def build_lesson(slot, date)
    Lesson.new(lesson_slot: slot, date: date, starts_at: at(date, slot.start_time), ends_at: at(date, slot.end_time))
  end

  def at(date, time)
    Time.zone.local(date.year, date.month, date.day, time.hour, time.min, time.sec)
  end
end
