require "rails_helper"

RSpec.describe MakeupReservationPolicy do
  %i[new? confirm? create? show?].each do |action|
    it "#{action} は、保護者だけに許可する" do
      expect(described_class.new(build(:guardian), :makeup_reservation).public_send(action)).to be true
      expect(described_class.new(build(:teacher), :makeup_reservation).public_send(action)).to be false
      expect(described_class.new(nil, :makeup_reservation).public_send(action)).to be false
    end
  end
end
