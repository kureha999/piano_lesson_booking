# 固定枠。一覧は先生だけが見られる（保護者は、自分の子どもの予定を別の画面で見る）。
class LessonSlotPolicy < ApplicationPolicy
  def index?
    user&.teacher? || false
  end

  class Scope < ApplicationPolicy::Scope
    # 先生はすべての固定枠、保護者は自分の子どもの固定枠だけ。ログインしていなければ何も返さない
    def resolve
      return scope.none if user.nil?

      user.teacher? ? scope.all : scope.where(student_id: user.students.select(:id))
    end
  end
end
