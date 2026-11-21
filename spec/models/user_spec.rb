require "rails_helper"

RSpec.describe User, type: :model do
  describe "factory" do
    it "保護者と先生の factory が有効である" do
      expect(build(:user)).to be_valid
      expect(build(:guardian)).to be_valid
      expect(build(:teacher)).to be_valid
    end
  end

  describe "role" do
    it "初期値は保護者（0）である" do
      expect(described_class.new).to be_guardian
      expect(described_class.columns_hash["role"].default).to eq "0"
    end

    it "先生は 1 として保存される" do
      expect(create(:teacher).role_before_type_cast).to eq 1
    end
  end

  describe "バリデーション" do
    it "名前が必須である" do
      user = build(:user, name: "")

      expect(user).not_to be_valid
      expect(user.errors.full_messages).to include "名前を入力してください"
    end

    it "メールアドレスが必須である" do
      expect(build(:user, email: "")).not_to be_valid
    end

    it "メールアドレスは大文字小文字を区別せず、重複できない" do
      create(:user, email: "taro@example.com")

      expect(build(:user, email: "TARO@example.com")).not_to be_valid
    end

    it "パスワードが短いと無効になる" do
      expect(build(:user, password: "short")).not_to be_valid
    end
  end

  describe "先生は1人だけ" do
    it "先生が2人目だと、モデルのバリデーションで無効になる" do
      create(:teacher)

      second = build(:teacher)
      expect(second).not_to be_valid
      expect(second.errors.full_messages).to include "役割の先生はすでに登録されています"
    end

    it "バリデーションを通さなくても、DB の制約で2人目の先生を作れない" do
      create(:teacher)

      expect { build(:teacher).save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "保護者は何人でも作れる" do
      create(:teacher)

      expect { create_list(:guardian, 3) }.to change(described_class.guardian, :count).by(3)
    end
  end
end
