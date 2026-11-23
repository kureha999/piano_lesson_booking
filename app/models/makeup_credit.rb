# 振替権。欠席1回に1つ付き、期限（expires_on）までの振替枠の予約に使う（README 12-2）。
# 状態（未使用・予約済み・使用済み・期限切れ）は保存せず、予約と期限から判定する（README 12-6）。
class MakeupCredit < ApplicationRecord
  belongs_to :student
  belongs_to :absence

  # 予約の履歴を残すため、予約がある振替権は削除できない（キャンセルした予約も含む）
  has_many :makeup_reservations, dependent: :restrict_with_error

  validates :expires_on, presence: true
  validates :absence_id, uniqueness: { message: "にはすでに振替権が付いています" }, allow_nil: true
  validate :student_must_be_the_absent_student

  private

  # 振替権の生徒は、欠席した生徒と同じであること
  def student_must_be_the_absent_student
    absent_student_id = absence&.lesson_slot&.student_id
    return if student_id.blank? || absent_student_id.blank?

    errors.add(:student, "は欠席した生徒と同じである必要があります") if student_id != absent_student_id
  end
end
