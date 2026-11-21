module Teacher
  # T-01 ダッシュボード（先生）。中身は今後の issue で作る。
  class DashboardController < ApplicationController
    def show
      authorize [ :teacher, :dashboard ]
    end
  end
end
