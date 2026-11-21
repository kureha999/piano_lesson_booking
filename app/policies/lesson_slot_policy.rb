# 固定枠。一覧・登録・変更は先生だけができる（保護者は、自分の子どもの予定を別の画面で見る）。
class LessonSlotPolicy < ApplicationPolicy
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
    # 先生はすべての固定枠、保護者は自分の子どもの固定枠だけ。ログインしていなければ何も返さない
    def resolve
      return scope.none if user.nil?

      user.teacher? ? scope.all : scope.where(student_id: user.students.select(:id))
    end
  end

  private

  def teacher?
    user&.teacher? || false
  end
end
