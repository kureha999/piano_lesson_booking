# 振替枠。一覧・登録・編集は先生だけができる（保護者向けの「予約できる枠」は、期限・締切・定員を見て絞る別の画面で扱う）。
class MakeupSlotPolicy < ApplicationPolicy
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
    # 先生はすべての振替枠。保護者は、この段階では何も返さない（予約できる枠の絞り込みは、予約の画面で作る）
    def resolve
      user&.teacher? ? scope.all : scope.none
    end
  end

  private

  def teacher?
    user&.teacher? || false
  end
end
