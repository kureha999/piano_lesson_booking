# P-05 予定一覧（保護者）。子どもごとの固定レッスン・振替予約・未使用の振替権を表示する。
# 未使用の振替権の「振替を選ぶ」から、振替枠を予約できる（MakeupReservationsController）。
class SchedulesController < ApplicationController
  def show
    authorize :schedule

    # 自分の子どもだけ（ほかの家庭の子どもは含まれない）
    @summaries = GuardianSchedule.new(policy_scope(Student)).summaries
  end
end
