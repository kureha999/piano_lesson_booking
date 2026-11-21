module Teacher
  # T-02 生徒一覧（先生）。追加・編集（T-03）は別の issue で作る。
  class StudentsController < ApplicationController
    def index
      authorize Student
      @students = policy_scope(Student).includes(:guardian).order(:id)
    end
  end
end
