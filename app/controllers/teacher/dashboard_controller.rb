module Teacher
  # T-01 ダッシュボード（先生）。今週の欠席と振替予約を、日付順に表示する（F-06）。
  # 初期設定の残り手順は、#52 で追加する。
  class DashboardController < ApplicationController
    def show
      authorize [ :teacher, :dashboard ]

      agenda = WeeklyAgenda.new
      @week = agenda.week
      @entries = agenda.entries
    end
  end
end
