require "rails_helper"

RSpec.describe StudentForm do
  let(:attributes) { { name: "たろう", guardian_name: "山田花子", guardian_email: "hanako@example.com" } }

  describe "登録（新しいメールアドレス）" do
    it "保護者を作ってから、生徒を追加する" do
      form = described_class.new(**attributes)

      expect { expect(form.save).to be true }.to change(User.guardian, :count).by(1).and change(Student, :count).by(1)
      expect(form.student).to have_attributes(name: "たろう", guardian: form.guardian)
      expect(form.guardian).to have_attributes(name: "山田花子", email: "hanako@example.com", role: "guardian")
      expect(form).to be_guardian_created
    end

    it "保護者のパスワードは、推測できない値になる（本人が設定するまでログインできない）" do
      form = described_class.new(**attributes)
      form.save

      expect(form.guardian.encrypted_password).to be_present
      expect(form.guardian.valid_password?("password")).to be false
    end

    it "メールアドレスの前後の空白と大文字は、取り除いて保存する" do
      form = described_class.new(**attributes, guardian_email: "  Hanako@Example.com ")
      form.save

      expect(form.guardian.email).to eq "hanako@example.com"
    end
  end

  describe "登録（登録済みのメールアドレス）" do
    let!(:guardian) { create(:guardian, name: "山田花子", email: "hanako@example.com") }

    it "同じメールアドレスで2人目を登録すると、保護者は1人のまま、生徒が2人になる" do
      create(:student, guardian: guardian, name: "はなこ")

      form = described_class.new(**attributes)

      expect { expect(form.save).to be true }.to not_change(User.guardian, :count).and change(Student, :count).by(1)
      expect(guardian.students.pluck(:name)).to contain_exactly "はなこ", "たろう"
      expect(form.guardian).to eq guardian
      expect(form).not_to be_guardian_created
    end

    it "大文字・前後の空白が違っていても、同じ保護者として扱う" do
      form = described_class.new(**attributes, guardian_email: " HANAKO@example.com")

      expect { form.save }.not_to change(User, :count)
      expect(form.student.guardian).to eq guardian
    end

    it "入力した保護者の名前では、登録済みの名前を書き換えない" do
      described_class.new(**attributes, guardian_name: "別の名前").save

      expect(guardian.reload.name).to eq "山田花子"
    end

    it "保護者の名前が空でも登録できる（登録済みの名前を使う）" do
      form = described_class.new(**attributes, guardian_name: "")

      expect(form.save).to be true
    end
  end

  describe "登録（入力エラー）" do
    it "生徒の呼び名が空だと、保存しない" do
      form = described_class.new(**attributes, name: "")

      expect { expect(form.save).to be false }.not_to change(Student, :count)
      expect(form.errors.full_messages_for(:name)).to eq [ "生徒の呼び名を入力してください" ]
    end

    it "新しい保護者の名前が空だと、保存しない" do
      form = described_class.new(**attributes, guardian_name: "")

      expect { expect(form.save).to be false }.not_to change(User, :count)
      expect(form.errors.full_messages_for(:guardian_name)).to eq [ "保護者の名前を入力してください" ]
    end

    it "メールアドレスが空・形式が正しくないと、保存しない" do
      [ "", "hanako", "hanako@" ].each do |invalid|
        form = described_class.new(**attributes, guardian_email: invalid)

        expect(form.save).to be(false), "#{invalid.inspect} は保存できないはず"
        expect(form.errors[:guardian_email]).to be_present
      end
    end

    it "すべての入力エラーを、同時に返す" do
      form = described_class.new(name: "", guardian_name: "", guardian_email: "")

      form.save

      expect(form.errors.attribute_names).to contain_exactly :name, :guardian_name, :guardian_email
    end

    it "先生のメールアドレスは使えない" do
      teacher = create(:teacher)
      form = described_class.new(**attributes, guardian_email: teacher.email)

      expect { expect(form.save).to be false }.not_to change(Student, :count)
      expect(form.errors.full_messages_for(:guardian_email).first).to include "先生のメールアドレス"
    end

    it "エラーのときは、保護者も生徒も作らない（途中まで保存しない）" do
      form = described_class.new(**attributes, name: "")

      expect { form.save }.not_to change { [ User.count, Student.count ] }
    end
  end

  describe "同時に同じメールアドレスで登録されたとき" do
    it "作られた保護者を探し直して、その保護者に生徒を追加する" do
      form = described_class.new(**attributes)
      calls = 0
      # 検証は通ったが、保存する直前に、別の人が同じメールアドレスの保護者を作っていた状況をつくる
      allow(form).to receive(:valid_for_create?).and_wrap_original do |original|
        result = original.call
        calls += 1
        create(:guardian, email: "hanako@example.com", name: "先に作られた") if calls == 1
        result
      end

      expect(form.save).to be true
      expect(User.where(email: "hanako@example.com").count).to eq 1
      expect(form.student.guardian.name).to eq "先に作られた"
    end
  end

  describe "編集" do
    let!(:student) { create(:student, name: "たろう", guardian: create(:guardian, name: "山田花子", email: "hanako@example.com")) }

    it "登録済みの生徒の値で、フォームを作れる" do
      form = described_class.for(student)

      expect(form).to be_persisted
      expect(form).to have_attributes(name: "たろう", guardian_name: "山田花子", guardian_email: "hanako@example.com")
    end

    it "生徒の呼び名と、保護者の名前・メールアドレスを更新する" do
      form = described_class.new(student: student, name: "たろ", guardian_name: "山田はな", guardian_email: "new@example.com")

      expect(form.save).to be true
      expect(student.reload.name).to eq "たろ"
      expect(student.guardian).to have_attributes(name: "山田はな", email: "new@example.com")
    end

    it "保護者の変更は、同じ保護者のほかの生徒にも反映される" do
      sibling = create(:student, guardian: student.guardian)

      described_class.new(student: student, name: "たろう", guardian_name: "新しい名前", guardian_email: "hanako@example.com").save

      expect(sibling.reload.guardian.name).to eq "新しい名前"
    end

    it "ほかの保護者のメールアドレスには変更できない" do
      other = create(:guardian)
      form = described_class.new(student: student, name: "たろう", guardian_name: "山田花子", guardian_email: other.email)

      expect(form.save).to be false
      expect(form.errors[:guardian_email]).to be_present
      expect(student.guardian.reload.email).to eq "hanako@example.com"
    end

    it "入力エラーを、すべて同時に返し、何も更新しない" do
      form = described_class.new(student: student, name: "", guardian_name: "", guardian_email: "")

      expect(form.save).to be false
      expect(form.errors.attribute_names).to contain_exactly :name, :guardian_name, :guardian_email
      expect(student.reload.name).to eq "たろう"
    end

    it "自分のメールアドレスのままなら、重複エラーにならない" do
      form = described_class.for(student)

      expect(form.save).to be true
    end
  end
end
