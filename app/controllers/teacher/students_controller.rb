module Teacher
  # T-02 生徒一覧、T-03 生徒の登録・編集（先生）
  class StudentsController < ApplicationController
    def index
      authorize Student
      @students = policy_scope(Student).includes(:guardian).order(:id)
    end

    def new
      authorize Student
      @form = StudentForm.new
    end

    def create
      authorize Student
      @form = StudentForm.new(**form_params)

      if @form.save
        redirect_to teacher_students_path, notice: created_message(@form)
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

    def created_message(form)
      if form.guardian_created?
        "#{form.name}さんと保護者（#{form.guardian.name}さん）を登録しました。"
      else
        "登録済みの保護者（#{form.guardian.name}さん）に、#{form.name}さんを追加しました。"
      end
    end
  end
end
