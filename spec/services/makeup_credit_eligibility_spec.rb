require "rails_helper"

RSpec.describe MakeupCreditEligibility do
  let(:student) { create(:student) }
  let(:slot) { create(:lesson_slot, student: student, wday: 3, start_time: "16:00", end_time: "16:30") }
  let(:absence) { Absence.new(lesson_slot: slot, lesson_on: Date.new(2026, 11, 11)) } # 保存しない

  before { travel_to Time.zone.local(2026, 11, 2, 9, 0) }

  it "締切前で、月の上限内なら、振替権が付く（保存していない欠席でも判定できる）" do
    eligibility = described_class.new(absence)

    expect(eligibility).to be_eligible
    expect(eligibility.no_credit_reason).to be_nil
    expect(eligibility.expires_on).to eq Date.new(2026, 12, 11)
  end

  it "締切ちょうどまでは付き、過ぎると「締切後」になる" do
    travel_to Time.zone.local(2026, 11, 11, 14, 0)
    expect(described_class.new(absence)).to be_eligible

    travel_to Time.zone.local(2026, 11, 11, 14, 0, 1)
    expect(described_class.new(absence).no_credit_reason).to eq :after_deadline
  end

  it "月の上限に達していたら「月の上限」になる" do
    create(:absence, lesson_slot: slot, lesson_on: Date.new(2026, 11, 4))
    create(:absence, lesson_slot: slot, lesson_on: Date.new(2026, 11, 18))

    eligibility = described_class.new(absence)

    expect(eligibility).not_to be_eligible
    expect(eligibility.no_credit_reason).to eq :over_monthly_limit
  end

  it "締切後の判定が先（締切後で、上限にも達しているときは「締切後」）" do
    create(:absence, lesson_slot: slot, lesson_on: Date.new(2026, 11, 4))
    create(:absence, lesson_slot: slot, lesson_on: Date.new(2026, 11, 18))
    travel_to Time.zone.local(2026, 11, 11, 15, 0)

    expect(described_class.new(absence).no_credit_reason).to eq :after_deadline
  end

  it "ルールを引数で渡せる" do
    rule = MakeupRule.new(valid_days: 10, absence_deadline_hours: 2, monthly_limit: 2)

    expect(described_class.new(absence, rule: rule).expires_on).to eq Date.new(2026, 11, 21)
  end
end
