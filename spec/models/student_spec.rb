require "rails_helper"

RSpec.describe Student, type: :model do
  it "factory が有効である" do
    expect(build(:student)).to be_valid
  end

  describe "関連" do
    it "保護者（User）に属する" do
      guardian = create(:guardian)
      student = create(:student, guardian: guardian)

      expect(student.guardian).to eq guardian
      expect(student.guardian_id).to eq guardian.id
    end

    it "保護者は、複数の生徒（兄弟）を持てる" do
      guardian = create(:guardian)
      siblings = create_list(:student, 2, guardian: guardian)

      expect(guardian.students).to match_array siblings
    end

    it "ほかの保護者の生徒は含まない" do
      mine = create(:student)
      create(:student)

      expect(mine.guardian.students).to contain_exactly mine
    end

    it "生徒がいる保護者は、削除できない" do
      student = create(:student)

      expect(student.guardian.destroy).to be false
      expect(student.guardian.errors).not_to be_empty
      expect(described_class.exists?(student.id)).to be true
    end
  end

  describe "バリデーション" do
    it "名前が必須である" do
      student = build(:student, name: "")

      expect(student).not_to be_valid
      expect(student.errors.full_messages).to include "名前を入力してください"
    end

    it "保護者が必須である" do
      expect(build(:student, guardian: nil)).not_to be_valid
    end

    it "先生には紐づけられない" do
      student = build(:student, guardian: create(:teacher))

      expect(student).not_to be_valid
      expect(student.errors.full_messages).to include "保護者は保護者である必要があります"
    end
  end

  describe "DB の制約" do
    it "存在しない保護者は指定できない（外部キー制約）" do
      student = build(:student)
      student.guardian_id = 0

      expect { student.save!(validate: false) }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "guardian_id が NULL のデータは保存できない" do
      student = build(:student, guardian: nil)

      expect { student.save!(validate: false) }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "name が NULL のデータは保存できない" do
      student = build(:student, name: nil)

      expect { student.save!(validate: false) }.to raise_error(ActiveRecord::NotNullViolation)
    end
  end
end
