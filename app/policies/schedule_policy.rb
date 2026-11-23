# P-05 予定一覧。保護者だけが開ける（先生は、ダッシュボードや生徒一覧で確認する）。
# 表示する子どもは、policy_scope(Student) で自分の子どもに絞る。
class SchedulePolicy < ApplicationPolicy
  def show?
    user.present? && user.guardian?
  end
end
