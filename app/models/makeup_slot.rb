# 振替枠。先生が登録する、振替を受け付ける日時と定員（README 12-6）。
# 先生は1人なので、振替枠どうしや、固定枠（毎週のレッスン）と時間が重なる枠は登録できない。
# 振替枠どうしの重なりは DB の排他制約（同時に登録されても破れない）、固定枠との重なりはこのモデルで確認する。
class MakeupSlot < ApplicationRecord
  validates :starts_at, :ends_at, presence: true
  validates :capacity, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1, allow_nil: true }
  validate :ends_at_after_starts_at
  validate :capacity_not_below_reserved_count
  validate :not_overlapping_other_makeup_slots
  validate :not_overlapping_lesson_slots

  # 指定した時間（開始〜終了）と重なる振替枠。接しているだけ（終了と開始が同じ）は重ならない
  scope :overlapping, ->(starts_at, ends_at) { where("starts_at < ? AND ends_at > ?", ends_at, starts_at) }

  # これから受け付ける枠（終了前の枠）。過去の枠は含めない。開始日時の順
  scope :upcoming, -> { where("ends_at > ?", Time.current).order(:starts_at) }

  # 予約の数。振替の予約（makeup_reservations）ができたら、有効な予約（canceled_at が NULL）の数を返す
  def reserved_count
    0
  end

  # 「6月13日 15:00〜15:30」
  def period_text
    "#{starts_at.strftime('%-m月%-d日 %H:%M')}〜#{ends_at.strftime('%H:%M')}"
  end

  private

  def times_present?
    starts_at.present? && ends_at.present? && ends_at > starts_at
  end

  # 予約がある枠は、定員を予約数より少なくできない
  def capacity_not_below_reserved_count
    return if capacity.blank? || capacity >= reserved_count

    errors.add(:capacity, "は、すでにある予約の数（#{reserved_count}件）以上にしてください")
  end

  def ends_at_after_starts_at
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, "は開始日時より後にしてください") unless ends_at > starts_at
  end

  def not_overlapping_other_makeup_slots
    return unless times_present?

    others = self.class.overlapping(starts_at, ends_at)
    others = others.where.not(id: id) if persisted?
    other = others.order(:starts_at).first
    errors.add(:base, "同じ時間に、ほかの振替枠があります（#{other.period_text}）") if other
  end

  # 固定枠の各回（適用期間内）と時間が重ならない。日付は日本時間で数える
  def not_overlapping_lesson_slots
    return unless times_present?

    period = starts_at.in_time_zone.to_date..ends_at.in_time_zone.to_date
    lesson = LessonSchedule.new(LessonSlot.includes(:student), period).lessons.find do |candidate|
      candidate.starts_at < ends_at && candidate.ends_at > starts_at
    end
    return unless lesson

    errors.add(:base, "固定枠（毎週のレッスン）の時間と重なっています（#{lesson.student.name}さん #{lesson.starts_at.strftime('%-m月%-d日 %H:%M')}〜#{lesson.ends_at.strftime('%H:%M')}）")
  end
end
