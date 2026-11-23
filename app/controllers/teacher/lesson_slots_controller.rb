module Teacher
  # T-04 固定枠の一覧、T-05 固定枠の登録・変更（先生）
  class LessonSlotsController < ApplicationController
    def index
      authorize LessonSlot
      @lesson_slots = effective_slots.includes(:student).in_weekly_order
    end

    def new
      authorize LessonSlot
      @form = LessonSlotForm.new(starts_on: Date.current)
      load_students
    end

    def create
      authorize LessonSlot
      @form = LessonSlotForm.new(**form_params)

      if @form.save
        redirect_to teacher_lesson_slots_path, notice: "#{@form.student.name}さんの固定枠を登録しました。"
      else
        load_students
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @form = LessonSlotForm.for(find_slot)
    end

    def update
      slot = find_slot
      @form = LessonSlotForm.new(lesson_slot: slot, **form_params.except(:student_id), student_id: slot.student_id)

      if @form.save
        redirect_to teacher_lesson_slots_path, notice: helpers.lesson_slot_updated_message(@form, slot)
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    # 今日に有効な枠だけ
    def effective_slots
      policy_scope(LessonSlot).effective_on(Date.current)
    end

    # 今日に有効でない枠（終了済み・まだ始まっていない枠）や、存在しない ID は、RecordNotFound になり、E-01（404）が表示される
    def find_slot
      slot = effective_slots.includes(:student).find(params[:id])
      authorize slot
      slot
    end

    def load_students
      @students = policy_scope(Student).order(:id)
    end

    def form_params
      params.expect(lesson_slot: %i[student_id wday start_time end_time starts_on]).to_h.symbolize_keys
    end
  end
end
