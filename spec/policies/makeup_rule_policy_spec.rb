require "rails_helper"

RSpec.describe MakeupRulePolicy do
  %i[update? edit?].each do |action|
    it "#{action} は、先生だけに許可する" do
      expect(described_class.new(build(:teacher), MakeupRule.current).public_send(action)).to be true
      expect(described_class.new(build(:guardian), MakeupRule.current).public_send(action)).to be false
      expect(described_class.new(nil, MakeupRule.current).public_send(action)).to be false
    end
  end
end
