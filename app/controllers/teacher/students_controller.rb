module Teacher
  # T-02 生徒一覧、T-03 生徒の登録・編集（先生）
  class StudentsController < ApplicationController
    def index
      authorize Student
      @students = policy_scope(Student).includes(:guardian).order(:id)
      # 今月（日本時間）の振替の利用回数（その月に振替権が付いた欠席の数）と、月の上限
      @usage_counts = MonthlyCreditUsage.counts(Date.current)
      @monthly_limit = MakeupRule.current.monthly_limit
    end

    def new
      authorize Student
      @form = StudentForm.new
    end

    def create
      authorize Student
      @form = StudentForm.new(invited_by: current_user, **form_params)

      if @form.save
        redirect_to teacher_students_path, helpers.student_created_flash(@form)
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @form = StudentForm.for(find_student)
    end

    def update
      @form = StudentForm.new(student: find_student, **form_params)

      if @form.save
        redirect_to teacher_students_path, notice: "#{@form.name}さんの情報を更新しました。"
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    # 存在しない生徒の ID は RecordNotFound になり、E-01（404）が表示される
    def find_student
      student = policy_scope(Student).includes(:guardian).find(params[:id])
      authorize student
      student
    end

    def form_params
      params.expect(student: %i[name guardian_name guardian_email]).to_h.symbolize_keys
    end
  end
end
