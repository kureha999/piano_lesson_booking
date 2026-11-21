# 先生のアカウントを作る。導入時に rake タスク（teacher:create）から呼ぶ。
# 先生は教室に1人だけ。すでにいる場合は、作らずにエラーを返す。
class CreateTeacher
  Result = Struct.new(:user, :errors) do
    def success? = errors.empty?
  end

  def self.call(...) = new(...).call

  def initialize(name:, email:, password:)
    @name = name
    @email = email
    @password = password
  end

  def call
    user = User.new(name: @name, email: @email, password: @password, role: :teacher)
    user.save ? Result.new(user, []) : Result.new(nil, user.errors.full_messages)
  rescue ActiveRecord::RecordNotUnique
    # 同時に実行されて、DB の制約（先生は1人・メールアドレスの重複）で止まった場合
    Result.new(nil, [ "先生またはメールアドレスがすでに登録されています" ])
  end
end
