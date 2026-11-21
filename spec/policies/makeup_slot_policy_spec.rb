require "rails_helper"

RSpec.describe MakeupSlotPolicy do
  it "一覧は、先生だけに許可する" do
    expect(described_class.new(build(:teacher), MakeupSlot).index?).to be true
    expect(described_class.new(build(:guardian), MakeupSlot).index?).to be false
    expect(described_class.new(nil, MakeupSlot).index?).to be false
  end

  it "登録・編集・削除・詳細は、まだ許可しない（画面がない）" do
    policy = described_class.new(build(:teacher), MakeupSlot)

    expect([ policy.create?, policy.update?, policy.destroy?, policy.show? ]).to all(be false)
  end

  describe "Scope" do
    let!(:slot) { create(:makeup_slot) }

    it "先生には、すべての振替枠を返す" do
      expect(described_class::Scope.new(create(:teacher), MakeupSlot).resolve).to contain_exactly(slot)
    end

    it "保護者とログインしていない人には、何も返さない" do
      expect(described_class::Scope.new(create(:guardian), MakeupSlot).resolve).to be_empty
      expect(described_class::Scope.new(nil, MakeupSlot).resolve).to be_empty
    end
  end
end
