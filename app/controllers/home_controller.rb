# P-01 ホーム（保護者）。子ども（兄弟を含む）ごとに、今後2週間のレッスン・今月の振替の残り回数・未使用の振替権を表示する。
# 先生が開いたら T-01 に移動する。
class HomeController < ApplicationController
  def show
    authorize :home

    return redirect_to teacher_root_path if current_user.teacher?

    # 自分の子どもだけ（ほかの家庭の子どもは含まれない）
    @summaries = GuardianHome.new(policy_scope(Student)).summaries
  end
end
