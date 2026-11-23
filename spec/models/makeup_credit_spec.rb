require "rails_helper"

RSpec.describe MakeupCredit do
  describe "factory" do
    it "有効な振替権を作る" do
      expect(build(:makeup_credit)).to be_valid
    end
  end

  describe "入力の検証" do
    it "生徒・欠席・期限は必須" do
      credit = described_class.new

      expect(credit).not_to be_valid
      expect(credit.errors.attribute_names).to include(:student, :absence, :expires_on)
    end

    it "欠席した生徒と違う生徒は指定できない" do
      credit = build(:makeup_credit, absence: create(:absence), student: create(:student))

      expect(credit).not_to be_valid
      expect(credit.errors[:student]).to include "は欠席した生徒と同じである必要があります"
    end
  end

  describe "欠席1回に振替権は1つ" do
    it "同じ欠席に2つ目の振替権は付けられない" do
      first = create(:makeup_credit)
      second = build(:makeup_credit, absence: first.absence)

      expect(second).not_to be_valid
      expect(second.errors[:absence_id]).to include "にはすでに振替権が付いています"
    end

    it "検証を通り抜けても、DB の一意インデックスが2つ目を止める" do
      first = create(:makeup_credit)
      second = build(:makeup_credit, absence: first.absence)

      expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "関連" do
    it "振替権がある生徒は、削除できない" do
      credit = create(:makeup_credit)

      expect(credit.student.destroy).to be false
    end

    it "欠席から振替権をたどれる" do
      credit = create(:makeup_credit)

      expect(credit.absence.makeup_credit).to eq credit
    end
  end
end
