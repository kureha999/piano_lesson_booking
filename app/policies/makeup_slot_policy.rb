# 振替枠。一覧は先生だけが見られる（保護者向けの「予約できる枠」は、期限・締切・定員を見て絞る別の画面で扱う）。
class MakeupSlotPolicy < ApplicationPolicy
  def index?
    user&.teacher? || false
  end

  class Scope < ApplicationPolicy::Scope
    # 先生はすべての振替枠。保護者は、この段階では何も返さない（予約できる枠の絞り込みは、予約の画面で作る）
    def resolve
      user&.teacher? ? scope.all : scope.none
    end
  end
end
