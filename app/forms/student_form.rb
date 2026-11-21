# 生徒と保護者をまとめて登録・編集するフォーム（T-03）。
# Student と User（保護者）の2つのモデルをまたぐので、Controller や Model に書かず、このクラスにまとめる。
#
# 登録：
#   - 登録済みのメールアドレスなら、その保護者に生徒を追加する（兄弟は1つのアカウントにまとめる）。保護者の名前は変えない
#   - 新しいメールアドレスなら、保護者を作ってから生徒を追加する
#   - 先生のメールアドレスは使えない
# 編集：生徒の呼び名と、保護者の名前・メールアドレスを変える。保護者の変更は、その保護者のすべての生徒に反映される。
class StudentForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  # モデルのエラーを、フォームのどの項目のエラーにするか
  FIELDS = { name: :guardian_name, email: :guardian_email }.freeze
  private_constant :FIELDS

  attribute :name, :string            # 生徒の呼び名
  attribute :guardian_name, :string   # 保護者の名前
  attribute :guardian_email, :string  # 保護者のメールアドレス

  attr_reader :student, :guardian

  validates :name, presence: true

  # フォームのパラメーター名（student[name] など）と、属性名の訳（activemodel.attributes.student）に使う
  def self.model_name
    ActiveModel::Name.new(self, nil, "Student")
  end

  # 登録済みの生徒から、編集用のフォームを作る
  def self.for(student)
    new(student: student, name: student.name, guardian_name: student.guardian.name, guardian_email: student.guardian.email)
  end

  def initialize(student: nil, **attributes)
    @student = student
    super(**attributes)
  end

  def persisted?
    student&.persisted? || false
  end

  # 登録したときに、新しい保護者を作ったか（false なら、登録済みの保護者に追加した）
  def guardian_created?
    @guardian_created || false
  end

  def save
    persisted? ? update_existing : create_new
  end

  private

  def create_new
    attempts = 0
    begin
      attempts += 1
      @guardian = find_or_build_guardian
      return false unless valid_for_create?

      persist_new_student
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # 検証のあと、保存の直前に、同じメールアドレスで保護者が作られたとき（DB の一意制約か、保存時の検証で止まる）は、
      # 作られた保護者を探し直して、もう一度だけ試す
      retry if attempts < 2
      errors.add(:guardian_email, "はすでに登録されています。もう一度お試しください")
      false
    end
  end

  def valid_for_create?
    ok = valid?
    if guardian.persisted?
      ok = reject_teacher && ok
    else
      ok = collect_errors_from(guardian) && ok
    end
    ok
  end

  def persist_new_student
    new_guardian = guardian.new_record?
    ActiveRecord::Base.transaction do
      guardian.save!
      @student = guardian.students.create!(name: name)
    end
    @guardian_created = new_guardian
    true
  end

  def update_existing
    @guardian = student.guardian
    student.name = name
    guardian.name = guardian_name
    guardian.email = guardian_email

    # 入力エラーをすべて同時に表示するため、先にまとめて検証する
    ok = valid?
    ok = collect_errors_from(guardian) && ok
    return false unless ok

    ActiveRecord::Base.transaction do
      guardian.save!
      student.save!
    end
    true
  rescue ActiveRecord::RecordNotUnique
    errors.add(:guardian_email, "はすでに登録されています")
    false
  end

  # 登録済みの保護者を探す。なければ、新しい保護者を作る。
  # 新しい保護者のパスワードは、本人が設定するまで使えない（招待メールで設定する）ため、推測できない値を入れる。
  def find_or_build_guardian
    User.find_by(email: normalized_email) ||
      User.new(name: guardian_name, email: normalized_email, role: :guardian, password: SecureRandom.base64(32))
  end

  def normalized_email
    guardian_email.to_s.strip.downcase
  end

  def reject_teacher
    return true unless guardian.teacher?

    errors.add(:guardian_email, "は先生のメールアドレスです。保護者のメールアドレスを入力してください")
    false
  end

  # 保護者のモデルのエラー（名前・メールアドレス）を、フォームの項目に移す。エラーがなければ true
  def collect_errors_from(user)
    user.validate
    user.errors.each do |error|
      field = FIELDS[error.attribute]
      errors.add(field, error.message) if field
    end
    FIELDS.keys.none? { |attribute| user.errors.include?(attribute) }
  end
end
