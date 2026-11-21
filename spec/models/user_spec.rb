require "rails_helper"

RSpec.describe User, type: :model do
  describe "factory" do
    it "保護者と先生の factory が有効である" do
      expect(build(:user)).to be_valid
      expect(build(:guardian)).to be_valid
      expect(build(:teacher)).to be_valid
    end
  end

  describe "バリデーション" do
    describe "name" do
      it "必須である" do
        user = build(:user, name: "")

        expect(user).not_to be_valid
        expect(user.errors.full_messages).to include "名前を入力してください"
      end

      it "空白だけでは登録できない" do
        expect(build(:user, name: "  ")).not_to be_valid
      end
    end

    describe "email" do
      it "必須である" do
        user = build(:user, email: "")

        expect(user).not_to be_valid
        expect(user.errors.full_messages).to include "メールアドレスを入力してください"
      end

      it "形式が正しくないと無効になる" do
        %w[taro taro@ @example.com taro@@example.com].each do |invalid|
          expect(build(:user, email: invalid)).not_to be_valid, "#{invalid} は無効のはず"
        end
      end

      it "形式が正しければ有効になる" do
        expect(build(:user, email: "taro.yamada+piano@example.co.jp")).to be_valid
      end

      it "大文字小文字を区別せず、重複できない" do
        create(:user, email: "taro@example.com")
        duplicate = build(:user, email: "TARO@example.com")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors.full_messages).to include "メールアドレスはすでに存在します"
      end

      it "前後の空白と大文字は取り除いて保存する" do
        user = create(:user, email: "  Taro@Example.com ")

        expect(user.reload.email).to eq "taro@example.com"
      end

      it "バリデーションを通さなくても、DB の制約で重複できない" do
        create(:user, email: "taro@example.com")

        expect { build(:user, email: "taro@example.com").save!(validate: false) }
          .to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    describe "password" do
      it "新規作成では必須である" do
        expect(build(:user, password: "")).not_to be_valid
      end

      it "6文字未満だと無効になる" do
        user = build(:user, password: "12345")

        expect(user).not_to be_valid
        expect(user.errors.full_messages.join).to include "パスワード", "6文字以上"
      end

      it "6文字以上128文字以下なら有効になる" do
        expect(build(:user, password: "a" * 6)).to be_valid
        expect(build(:user, password: "a" * 128)).to be_valid
      end

      it "129文字以上だと無効になる" do
        expect(build(:user, password: "a" * 129)).not_to be_valid
      end

      it "確認用と一致しないと無効になる" do
        user = build(:user, password: "password123", password_confirmation: "different")

        expect(user).not_to be_valid
      end

      it "平文では保存せず、ハッシュにして保存する" do
        user = create(:user, password: "password123")

        expect(user.encrypted_password).not_to include "password123"
        expect(user.valid_password?("password123")).to be true
        expect(user.valid_password?("wrong")).to be false
      end

      it "パスワードを変えずに、ほかの項目だけ更新できる" do
        user = described_class.find(create(:user).id)

        expect(user.update(name: "新しい名前")).to be true
      end
    end
  end

  describe "role" do
    it "初期値は保護者（0）である" do
      expect(described_class.new).to be_guardian
      expect(described_class.columns_hash["role"].default).to eq "0"
    end

    it "保護者は 0、先生は 1 として保存される" do
      expect(described_class.roles).to eq("guardian" => 0, "teacher" => 1)
      expect(create(:guardian).role_before_type_cast).to eq 0
      expect(create(:teacher).role_before_type_cast).to eq 1
    end

    it "guardian? と teacher? で、ロールを判定できる" do
      guardian = build(:guardian)
      teacher = build(:teacher)

      expect(guardian).to be_guardian
      expect(guardian).not_to be_teacher
      expect(teacher).to be_teacher
      expect(teacher).not_to be_guardian
    end

    it "role を指定して、保護者と先生を絞り込める" do
      guardian = create(:guardian)
      teacher = create(:teacher)

      expect(described_class.guardian).to contain_exactly guardian
      expect(described_class.teacher).to contain_exactly teacher
    end

    it "定義にない値は指定できない" do
      expect { build(:user, role: :admin) }.to raise_error(ArgumentError)
    end
  end

  describe "先生は1人だけ" do
    it "先生が2人目だと、モデルのバリデーションで無効になる" do
      create(:teacher)

      second = build(:teacher)
      expect(second).not_to be_valid
      expect(second.errors.full_messages).to include "役割の先生はすでに登録されています"
    end

    it "保護者を先生に変えようとしても、すでに先生がいれば無効になる" do
      create(:teacher)
      guardian = create(:guardian)

      expect(guardian.update(role: :teacher)).to be false
    end

    it "バリデーションを通さなくても、DB の制約で2人目の先生を作れない" do
      create(:teacher)

      expect { build(:teacher).save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "DB の制約で、保護者を先生に変更することもできない" do
      create(:teacher)
      guardian = create(:guardian)

      expect { guardian.update_column(:role, 1) }.to raise_error(ActiveRecord::RecordNotUnique) # rubocop:disable Rails/SkipsModelValidations
    end

    it "先生本人の情報は、これまでどおり更新できる" do
      teacher = create(:teacher)

      expect(teacher.update(name: "新しい名前")).to be true
    end

    it "保護者は何人でも作れる" do
      create(:teacher)

      expect { create_list(:guardian, 3) }.to change(described_class.guardian, :count).by(3)
    end

    it "先生を削除すれば、新しい先生を作れる" do
      create(:teacher).destroy

      expect(build(:teacher)).to be_valid
    end
  end

  describe "DB の制約" do
    it "名前が NULL のデータは保存できない" do
      expect { build(:user, name: nil).save!(validate: false) }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "role が NULL のデータは保存できない" do
      user = build(:user)
      user.role = nil

      expect { user.save!(validate: false) }.to raise_error(ActiveRecord::NotNullViolation)
    end
  end
end
