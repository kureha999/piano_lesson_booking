require "rails_helper"

RSpec.describe HomePolicy do
  it "ログインしていれば、先生も保護者も P-01 を開ける" do
    expect(described_class.new(build(:guardian), :home).show?).to be true
    expect(described_class.new(build(:teacher), :home).show?).to be true
  end

  it "ログインしていなければ開けない" do
    expect(described_class.new(nil, :home).show?).to be false
  end
end
