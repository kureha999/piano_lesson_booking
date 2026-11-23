# 生徒。保護者（User）に属し、ログインはしない（README 12-3）。
class Student < ApplicationRecord
  belongs_to :guardian, class_name: "User", inverse_of: :students

  # 毎週の固定枠。履歴（欠席）が指すので、固定枠がある生徒は削除できない
  has_many :lesson_slots, dependent: :restrict_with_error
  # 欠席（固定枠をたどる）。月の上限の計算などに使う
  has_many :absences, through: :lesson_slots
  # 振替権。履歴なので、振替権がある生徒は削除できない
  has_many :makeup_credits, dependent: :restrict_with_error
  # 振替予約。履歴なので、予約がある生徒は削除できない
  has_many :makeup_reservations, dependent: :restrict_with_error

  validates :name, presence: true
  validate :guardian_must_be_guardian

  # 指定した日が属する月（日本時間の1日〜末日）に、振替権が付いた欠席の数。月の上限の計算に使う（README 12-2）
  def credited_absence_count_in_month(date)
    absences.where(no_credit_reason: nil, lesson_on: date.all_month).count
  end

  private

  # 生徒を持てるのは保護者だけ。先生には紐づけない（大人の生徒は、本人が保護者として登録する）
  def guardian_must_be_guardian
    errors.add(:guardian, "は保護者である必要があります") if guardian&.teacher?
  end
end
