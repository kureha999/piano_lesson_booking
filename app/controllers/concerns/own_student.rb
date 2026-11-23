# URL の子ども（params[:student_id]）を、自分の子どもに絞って探す。
# ほかの家庭の子どもは RecordNotFound（E-01：404）になる。保護者の画面で共通。
module OwnStudent
  extend ActiveSupport::Concern

  private

  def set_student
    @student = policy_scope(Student).find(params[:student_id])
  end
end
