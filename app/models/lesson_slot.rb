# 毎週のレッスンの固定枠。曜日・時間と、その枠が有効な期間を持つ。
# 毎回のレッスンは保存せず、ここから日付を計算する（README 12-6）。
# 曜日や時間を変えるときは、上書きせずに、今の枠へ適用終了日（ends_on）を入れて新しい枠を作る（過去の欠席の履歴を壊さないため）。
class LessonSlot < ApplicationRecord
  belongs_to :student

  validates :wday, presence: true, inclusion: { in: 0..6, allow_nil: true, message: "は日曜日〜土曜日のいずれかを選んでください" }
  validates :start_time, :end_time, :starts_on, presence: true
  validate :end_time_after_start_time
  validate :ends_on_not_before_starts_on
  validate :not_overlapping_other_slots

  # 期間の重なる枠。ends_on が NULL の枠は、終わりなしとして扱う
  scope :overlapping_period, lambda { |starts_on, ends_on|
    slots = where("ends_on IS NULL OR ends_on >= ?", starts_on)
    ends_on ? slots.where("starts_on <= ?", ends_on) : slots
  }

  # 指定した日に有効な枠（適用期間内）。適用終了日を過ぎた枠・まだ始まっていない枠は含まない
  scope :effective_on, ->(date) { where(starts_on: ..date).where("ends_on IS NULL OR ends_on >= ?", date) }

  # 曜日・開始時刻の順
  scope :in_weekly_order, -> { order(:wday, :start_time, :id) }

  # 「水曜日」のような曜日の名前
  def wday_name
    I18n.t("date.day_names")[wday]
  end

  # 「16:00〜16:30」
  def time_range
    "#{start_time.strftime('%H:%M')}〜#{end_time.strftime('%H:%M')}"
  end

  private

  def end_time_after_start_time
    return if start_time.blank? || end_time.blank?

    errors.add(:end_time, "は開始時刻より後にしてください") unless end_time > start_time
  end

  def ends_on_not_before_starts_on
    return if starts_on.blank? || ends_on.blank?

    errors.add(:ends_on, "は適用開始日以降にしてください") if ends_on < starts_on
  end

  # 先生は1人なので、同じ曜日で、時間も期間も重なる固定枠は登録できない
  # （生徒が違っても重なってはいけない。同じ生徒でも、重なる枠は二重になるので登録できない）
  def not_overlapping_other_slots
    return if [ wday, start_time, end_time, starts_on ].any?(&:blank?) || errors.any?

    overlapping = self.class.where(wday: wday)
      .where("start_time < ? AND end_time > ?", end_time, start_time)
      .overlapping_period(starts_on, ends_on)
    overlapping = overlapping.where.not(id: id) if persisted?
    errors.add(:base, "同じ曜日・時間・期間に、ほかの固定枠があります") if overlapping.exists?
  end
end
