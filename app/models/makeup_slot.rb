# 振替枠。先生が登録する、振替を受け付ける日時と定員（README 12-6）。
# 先生は1人なので、振替枠どうしや、固定枠（毎週のレッスン）と時間が重なる枠は登録できない。
# 振替枠どうしの重なりは DB の排他制約（同時に登録されても破れない）、固定枠との重なりはこのモデルで確認する。
class MakeupSlot < ApplicationRecord
  validates :starts_at, :ends_at, presence: true
  validates :capacity, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1, allow_nil: true }
  validate :ends_at_after_starts_at
  validate :not_overlapping_other_makeup_slots
  validate :not_overlapping_lesson_slots

  # 指定した時間（開始〜終了）と重なる振替枠。接しているだけ（終了と開始が同じ）は重ならない
  scope :overlapping, ->(starts_at, ends_at) { where("starts_at < ? AND ends_at > ?", ends_at, starts_at) }

  private

  def times_present?
    starts_at.present? && ends_at.present? && ends_at > starts_at
  end

  def ends_at_after_starts_at
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, "は開始日時より後にしてください") unless ends_at > starts_at
  end

  def not_overlapping_other_makeup_slots
    return unless times_present?

    others = self.class.overlapping(starts_at, ends_at)
    others = others.where.not(id: id) if persisted?
    errors.add(:base, "同じ時間に、ほかの振替枠があります") if others.exists?
  end

  # 固定枠の各回（適用期間内）と時間が重ならない。日付は日本時間で数える
  def not_overlapping_lesson_slots
    return unless times_present?

    period = starts_at.in_time_zone.to_date..ends_at.in_time_zone.to_date
    overlaps = LessonSchedule.new(LessonSlot.all, period).lessons.any? do |lesson|
      lesson.starts_at < ends_at && lesson.ends_at > starts_at
    end
    errors.add(:base, "固定枠（毎週のレッスン）の時間と重なっています") if overlaps
  end
end
