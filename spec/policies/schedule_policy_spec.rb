require "rails_helper"

RSpec.describe SchedulePolicy do
  it "show? は、保護者だけに許可する" do
    expect(described_class.new(build(:guardian), :schedule).show?).to be true
    expect(described_class.new(build(:teacher), :schedule).show?).to be false
    expect(described_class.new(nil, :schedule).show?).to be false
  end
end
