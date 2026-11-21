module Teacher
  # T-04 固定枠の一覧（先生）。今日（日本時間）に有効な枠を、曜日・開始時刻の順に表示する
  class LessonSlotsController < ApplicationController
    def index
      authorize LessonSlot
      @lesson_slots = policy_scope(LessonSlot).effective_on(Date.current).includes(:student).in_weekly_order
    end
  end
end
