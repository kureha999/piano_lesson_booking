require "rails_helper"

RSpec.describe AbsencePolicy do
  %i[new? confirm? create?].each do |action|
    it "#{action} は、保護者だけに許可する" do
      expect(described_class.new(build(:guardian), :absence).public_send(action)).to be true
      expect(described_class.new(build(:teacher), :absence).public_send(action)).to be false
      expect(described_class.new(nil, :absence).public_send(action)).to be false
    end
  end
end
