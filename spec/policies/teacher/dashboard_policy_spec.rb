require "rails_helper"

RSpec.describe Teacher::DashboardPolicy do
  it "先生は T-01 を開ける" do
    expect(described_class.new(build(:teacher), :dashboard).show?).to be true
  end

  it "保護者は開けない" do
    expect(described_class.new(build(:guardian), :dashboard).show?).to be false
  end

  it "ログインしていなければ開けない" do
    expect(described_class.new(nil, :dashboard).show?).to be false
  end
end
