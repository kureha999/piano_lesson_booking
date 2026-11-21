require "rails_helper"

RSpec.describe CreateTeacher do
  let(:params) { { name: "山田先生", email: "teacher@example.com", password: "password123" } }

  it "先生を作り、そのメールアドレスとパスワードで認証できる" do
    result = described_class.call(**params)

    expect(result).to be_success
    expect(result.user).to be_persisted
    expect(result.user).to be_teacher
    expect(result.user.valid_password?("password123")).to be true
  end

  it "すでに先生がいる場合は、作らずにエラーを返す" do
    create(:teacher)

    result = nil
    expect { result = described_class.call(**params) }.not_to change(User, :count)
    expect(result).not_to be_success
    expect(result.errors).to include "役割の先生はすでに登録されています"
  end

  it "保護者がいても、先生を作れる" do
    create(:guardian)

    expect(described_class.call(**params)).to be_success
  end

  it "入力が足りないときは、エラーを返す" do
    result = described_class.call(name: "", email: "", password: "")

    expect(result).not_to be_success
    expect(result.errors).to include "名前を入力してください", "メールアドレスを入力してください", "パスワードを入力してください"
  end

  it "DB の制約で止まった場合も、エラーとして返す" do
    allow_any_instance_of(User).to receive(:save).and_raise(ActiveRecord::RecordNotUnique) # rubocop:disable RSpec/AnyInstance

    result = described_class.call(**params)

    expect(result).not_to be_success
    expect(result.errors).to eq [ "先生またはメールアドレスがすでに登録されています" ]
  end
end
