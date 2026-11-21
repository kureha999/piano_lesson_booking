require "rails_helper"

RSpec.describe LessonSlotPolicy do
  # 一覧・登録（new?）・変更（edit?）は先生だけ。保護者とログインしていない人は、どれも許可しない
  %i[index? create? new? update? edit?].each do |action|
    it "#{action} は、先生だけに許可する" do
      expect(described_class.new(build(:teacher), LessonSlot).public_send(action)).to be true
      expect(described_class.new(build(:guardian), LessonSlot).public_send(action)).to be false
      expect(described_class.new(nil, LessonSlot).public_send(action)).to be false
    end
  end

  it "詳細表示と削除は、先生にも許可しない（画面がない）" do
    policy = described_class.new(build(:teacher), LessonSlot)

    expect([ policy.show?, policy.destroy? ]).to all(be false)
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
