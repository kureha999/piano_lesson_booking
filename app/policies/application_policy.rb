# frozen_string_literal: true

# すべてのポリシーの土台。何も許可しないのが初期値で、許可する操作だけを各ポリシーで書く。
# 一覧は policy_scope（Scope#resolve）で、ログイン中のユーザーが見てよいデータだけに絞る。
# 絞った中に無いデータを find すると RecordNotFound になり、E-01（404）が表示される
# （ほかの家庭のデータは「存在すること」も伝えない）。
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NoMethodError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope
  end
end
