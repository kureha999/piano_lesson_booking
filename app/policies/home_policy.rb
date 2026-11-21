# P-01 ホーム。ログインしていれば、先生も保護者も開ける（先生は T-01 に移動する）。
class HomePolicy < ApplicationPolicy
  def show?
    user.present?
  end
end
