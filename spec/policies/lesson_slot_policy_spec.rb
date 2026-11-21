require "rails_helper"

RSpec.describe LessonSlotPolicy do
  it "一覧は、先生だけに許可する" do
    expect(described_class.new(build(:teacher), LessonSlot).index?).to be true
    expect(described_class.new(build(:guardian), LessonSlot).index?).to be false
    expect(described_class.new(nil, LessonSlot).index?).to be false
  end

  it "登録・編集・削除は、まだ許可しない（画面がない）" do
    policy = described_class.new(build(:teacher), LessonSlot)

    expect([ policy.create?, policy.update?, policy.destroy?, policy.show? ]).to all(be false)
  end

  describe "Scope" do
    let!(:guardian) { create(:guardian) }
    let!(:mine) { create(:lesson_slot, student: create(:student, guardian: guardian)) }
    let!(:others) { create(:lesson_slot, wday: 4) }

    it "先生には、すべての固定枠を返す" do
      expect(described_class::Scope.new(create(:teacher), LessonSlot).resolve).to contain_exactly(mine, others)
    end

    it "保護者には、自分の子どもの固定枠だけを返す" do
      expect(described_class::Scope.new(guardian, LessonSlot).resolve).to contain_exactly(mine)
    end

    it "ログインしていなければ、何も返さない" do
      expect(described_class::Scope.new(nil, LessonSlot).resolve).to be_empty
    end
  end
end
