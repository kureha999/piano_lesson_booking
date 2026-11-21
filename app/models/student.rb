# 生徒。保護者（User）に属し、ログインはしない（README 12-3）。
class Student < ApplicationRecord
  belongs_to :guardian, class_name: "User", inverse_of: :students

  validates :name, presence: true
  validate :guardian_must_be_guardian

  private

  # 生徒を持てるのは保護者だけ。先生には紐づけない（大人の生徒は、本人が保護者として登録する）
  def guardian_must_be_guardian
    errors.add(:guardian, "は保護者である必要があります") if guardian&.teacher?
  end
end
