require "rails_helper"

RSpec.describe ApplicationPolicy do
  # 何も許可しないのが初期値。許可する操作は、各ポリシーで書く
  %i[index? show? create? new? update? edit? destroy?].each do |action|
    it "#{action} は、先生にも保護者にも許可しない" do
      [ build(:teacher), build(:guardian), nil ].each do |user|
        expect(described_class.new(user, :anything).public_send(action)).to be(false), "#{user.inspect} に #{action} を許可している"
      end
    end
  end

  it "Scope#resolve は、各ポリシーで定義するまで使えない" do
    expect { described_class::Scope.new(build(:guardian), User).resolve }.to raise_error(NoMethodError, /resolve/)
  end
end
