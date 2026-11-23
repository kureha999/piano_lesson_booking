# 振替ルール。設定（表示・更新）は先生だけができる。
class MakeupRulePolicy < ApplicationPolicy
  def update?
    user&.teacher? || false
  end
end
