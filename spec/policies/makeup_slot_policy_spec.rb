require "rails_helper"

RSpec.describe MakeupSlotPolicy do
  # 一覧・登録（new?）・編集（edit?）は先生だけ。保護者とログインしていない人は、どれも許可しない
  %i[index? create? new? update? edit?].each do |action|
    it "#{action} は、先生だけに許可する" do
      expect(described_class.new(build(:teacher), MakeupSlot).public_send(action)).to be true
      expect(described_class.new(build(:guardian), MakeupSlot).public_send(action)).to be false
      expect(described_class.new(nil, MakeupSlot).public_send(action)).to be false
    end
  end

  it "詳細表示と削除は、先生にも許可しない（画面がない）" do
    policy = described_class.new(build(:teacher), MakeupSlot)

    expect([ policy.show?, policy.destroy? ]).to all(be false)
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
