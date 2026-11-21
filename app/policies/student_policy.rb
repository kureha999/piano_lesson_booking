# 生徒。一覧・登録・編集は先生だけができる。
# 保護者向けの画面（自分の子どもだけ）は、Scope で自分の生徒に絞って使う。
class StudentPolicy < ApplicationPolicy
  def index?
    teacher?
  end

  def create?
    teacher?
  end

  def update?
    teacher?
  end

  class Scope < ApplicationPolicy::Scope
    # 先生はすべての生徒、保護者は自分の子どもだけ。
    # ほかの家庭の生徒を find すると RecordNotFound になり、E-01（404）が表示される。
    def resolve
      return scope.none if user.nil?

      user.teacher? ? scope.all : scope.where(guardian_id: user.id)
    end
  end

  private

  def teacher?
    user&.teacher? || false
  end
end
