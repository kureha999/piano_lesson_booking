require "rails_helper"

RSpec.describe StudentPolicy do
  describe "#index?" do
    it "先生は許可する" do
      expect(described_class.new(build(:teacher), Student).index?).to be true
    end

    it "保護者とログインしていない人は許可しない" do
      expect(described_class.new(build(:guardian), Student).index?).to be false
      expect(described_class.new(nil, Student).index?).to be false
    end
  end

  it "一覧以外の操作は、まだ許可しない" do
    policy = described_class.new(build(:teacher), Student)

    expect([ policy.show?, policy.create?, policy.update?, policy.destroy? ]).to all(be false)
  end

  describe "Scope" do
    let!(:guardian) { create(:guardian) }
    let!(:mine) { create_list(:student, 2, guardian: guardian) }
    let!(:others) { create(:student) }

    it "先生には、すべての生徒を返す" do
      resolved = described_class::Scope.new(create(:teacher), Student).resolve

      expect(resolved).to contain_exactly(*mine, others)
    end

    it "保護者には、自分の子どもだけを返す" do
      resolved = described_class::Scope.new(guardian, Student).resolve

      expect(resolved).to match_array mine
    end

    it "ほかの家庭の生徒を find すると、RecordNotFound になる（E-01：404 になる）" do
      resolved = described_class::Scope.new(guardian, Student).resolve

      expect { resolved.find(others.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "ログインしていなければ、何も返さない" do
      expect(described_class::Scope.new(nil, Student).resolve).to be_empty
    end
  end
end
