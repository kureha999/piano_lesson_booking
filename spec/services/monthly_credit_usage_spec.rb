require "rails_helper"

RSpec.describe MonthlyCreditUsage do
  let(:student) { create(:student) }
  let(:slot) { create(:lesson_slot, student: student) } # 水曜日

  describe ".count" do
    it "指定した日が属する月に、振替権が付いた欠席の数を返す" do
      create(:absence, lesson_slot: slot, lesson_on: Date.new(2099, 1, 7))
      create(:absence, lesson_slot: slot, lesson_on: Date.new(2099, 1, 14))

      expect(described_class.count(student, Date.new(2099, 1, 31))).to eq 2
    end

    it "振替権が付かなかった欠席と、別の月の欠席は数えない" do
      create(:absence, :after_deadline, lesson_slot: slot, lesson_on: Date.new(2099, 1, 7))
      create(:absence, lesson_slot: slot, lesson_on: Date.new(2099, 2, 4))

      expect(described_class.count(student, Date.new(2099, 1, 1))).to eq 0
      expect(described_class.count(student, Date.new(2099, 2, 28))).to eq 1
    end

    it "ほかの生徒の欠席は数えない" do
      create(:absence)

      expect(described_class.count(student, Date.new(2099, 1, 7))).to eq 0
    end
  end

  describe ".counts" do
    let(:other) { create(:student) }

    before do
      create(:absence, lesson_slot: slot, lesson_on: Date.new(2099, 1, 7))
      create(:absence, lesson_slot: create(:lesson_slot, student: other, start_time: "17:00", end_time: "17:30"), lesson_on: Date.new(2099, 1, 7))
    end

    it "生徒ごとの数を返す（欠席がない生徒は含まない）" do
      create(:student)

      expect(described_class.counts(Date.new(2099, 1, 7))).to eq(student.id => 1, other.id => 1)
    end

    it "student_ids で、生徒を絞れる" do
      expect(described_class.counts(Date.new(2099, 1, 7), student_ids: [ other.id ])).to eq(other.id => 1)
    end
  end
end
