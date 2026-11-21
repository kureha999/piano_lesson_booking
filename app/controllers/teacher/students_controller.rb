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
      @form = StudentForm.new(invited_by: current_user, **form_params)

      if @form.save
        redirect_to teacher_students_path, created_flash(@form)
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

    # 登録後に表示するメッセージ。新しい保護者には招待メールを送るので、送れたかどうかも伝える
    def created_flash(form)
      return { notice: "登録済みの保護者（#{form.guardian.name}さん）に、#{form.name}さんを追加しました。" } unless form.guardian_created?

      message = "#{form.name}さんと保護者（#{form.guardian.name}さん）を登録しました。"
      if form.invitation_sent?
        { notice: "#{message}#{form.guardian.email} に、パスワード設定の招待メールを送りました。" }
      else
        { notice: message, alert: "招待メールを送れませんでした。保護者の方に、ログイン画面の「パスワードを忘れた方」からパスワードを設定してもらってください。" }
      end
    end
  end
end
