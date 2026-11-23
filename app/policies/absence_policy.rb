# 欠席の連絡（P-02〜P-04）。保護者だけができる（先生は、ダッシュボードで欠席を確認する）。
# どの子どもの欠席かは、policy_scope(Student) で自分の子どもに絞って探す（ほかの家庭の子どもは E-01：404）。
class AbsencePolicy < ApplicationPolicy
  def new?
    guardian?
  end

  def confirm?
    guardian?
  end

  def create?
    guardian?
  end

  private

  def guardian?
    user.present? && user.guardian?
  end
end
