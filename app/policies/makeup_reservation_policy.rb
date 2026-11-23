# 振替予約（未使用の振替権から振替枠を選ぶ流れ。P-02〜P-04）。保護者だけができる。
# どの振替権かは、policy_scope(Student) で自分の子どもに絞ってから、その子どもの振替権の中から探す（ほかの家庭は E-01：404）。
class MakeupReservationPolicy < ApplicationPolicy
  def new?
    guardian?
  end

  def confirm?
    guardian?
  end

  def create?
    guardian?
  end

  def show?
    guardian?
  end

  private

  def guardian?
    user.present? && user.guardian?
  end
end
