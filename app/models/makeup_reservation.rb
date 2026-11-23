# 振替予約。振替権（MakeupCredit）で、振替枠（MakeupSlot）を予約する（README 12-6）。
# キャンセルしても行は消さず、canceled_at に日時を入れる（履歴が残る）。canceled_at が NULL の予約が、有効な予約。
# 「1つの振替権で有効な予約は1つ」「同じ生徒が同じ枠を二重に予約しない」は、DB の部分一意インデックスでも守る。
class MakeupReservation < ApplicationRecord
  belongs_to :makeup_credit
  belongs_to :makeup_slot
  belongs_to :student

  validates :makeup_credit_id, uniqueness: { conditions: -> { active }, message: "にはすでに有効な予約があります" },
    if: -> { active? && makeup_credit_id }
  validates :student_id, uniqueness: { scope: :makeup_slot_id, conditions: -> { active }, message: "はすでにこの枠を予約しています" },
    if: -> { active? && student_id }
  validate :student_must_be_the_credit_owner

  # 有効な予約（キャンセルされていない）
  scope :active, -> { where(canceled_at: nil) }

  def active?
    canceled_at.nil?
  end

  def canceled?
    !active?
  end

  private

  # 予約する生徒は、振替権を持つ生徒と同じであること
  def student_must_be_the_credit_owner
    return if student_id.blank? || makeup_credit.blank?

    errors.add(:student, "は振替権を持つ生徒と同じである必要があります") if student_id != makeup_credit.student_id
  end
end
