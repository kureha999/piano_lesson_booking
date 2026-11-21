module Teacher
  # T-06 振替枠の一覧（先生）。これから受け付ける振替枠を、日付の順に表示する
  class MakeupSlotsController < ApplicationController
    def index
      authorize MakeupSlot
      @makeup_slots = policy_scope(MakeupSlot).upcoming
    end
  end
end
