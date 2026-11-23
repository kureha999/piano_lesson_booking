# 欠席。毎週のレッスンのうち、休む回だけを保存する（README 12-6）。
# 振替権（MakeupCredit）が付くのは、欠席連絡の締切までに連絡し、月の上限を超えていない欠席だけ。
# 付かなかった理由は no_credit_reason に残す（付く欠席は NULL）。
class Absence < ApplicationRecord
  belongs_to :lesson_slot
  belongs_to :reported_by, class_name: "User", inverse_of: :reported_absences

  # 欠席1回に振替権は1つまで。履歴なので、振替権がある欠席は削除できない
  has_one :makeup_credit, dependent: :restrict_with_error

  enum :no_credit_reason, { after_deadline: 0, over_monthly_limit: 1 }

  validates :lesson_on, presence: true
  validates :lesson_on, uniqueness: { scope: :lesson_slot_id, message: "のレッスンは、すでに欠席を連絡しています" }
  validate :lesson_on_must_be_a_lesson_day
  validate :lesson_must_not_have_started, on: :create

  # その欠席のレッスンの開始日時（日本時間）。固定枠か日付がないときは nil
  def lesson_starts_at
    return if lesson_slot.blank? || lesson_on.blank?

    time = lesson_slot.start_time
    Time.zone.local(lesson_on.year, lesson_on.month, lesson_on.day, time.hour, time.min)
  end

  private

  # 欠席する日は、固定枠の曜日で、適用期間内であること
  def lesson_on_must_be_a_lesson_day
    return if lesson_slot.blank? || lesson_on.blank?

    if lesson_on.wday != lesson_slot.wday
      errors.add(:lesson_on, "は固定枠の曜日（#{lesson_slot.wday_name}）ではありません")
    elsif lesson_on < lesson_slot.starts_on || (lesson_slot.ends_on && lesson_on > lesson_slot.ends_on)
      errors.add(:lesson_on, "は固定枠の適用期間外です")
    end
  end

  # 欠席できるのは、レッスンが始まる前だけ。始まった後に登録済みの欠席が無効にならないよう、作るときだけ確認する
  def lesson_must_not_have_started
    return if errors.include?(:lesson_on) || lesson_starts_at.blank?

    errors.add(:lesson_on, "のレッスンはすでに始まっています") if lesson_starts_at <= Time.current
  end
end
