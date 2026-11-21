module Teacher
  # T-01 ダッシュボード。先生だけが開ける。
  class DashboardPolicy < ApplicationPolicy
    def show?
      user&.teacher? || false
    end
  end
end
