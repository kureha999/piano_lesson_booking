# P-01 ホーム（保護者）。中身は今後の issue で作る。
class HomeController < ApplicationController
  def show
    redirect_to teacher_root_path if current_user.teacher?
  end
end
