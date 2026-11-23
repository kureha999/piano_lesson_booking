require "rails_helper"

RSpec.describe AbsenceMakeupChoices do
  # 2026年11月2日（月）の朝。欠席するのは、水曜日 16:00〜16:30 のレッスン（11/11）。振替の期限は 12/11
  let(:student) { create(:student) }
  let(:lesson_slot) { create(:lesson_slot, student: student, wday: 3, start_time: "16:00", end_time: "16:30") }
  let(:absence) { Absence.new(lesson_slot: lesson_slot, lesson_on: Date.new(2026, 11, 11)) } # 保存しない
  let(:choices) { described_class.new(student, absence) }
  let!(:makeup_slot) { create_makeup_slot(Date.new(2026, 11, 16)) }

  before { travel_to Time.zone.local(2026, 11, 2, 9, 0) }

  # ほかの生徒（火曜日の固定枠）が予約して、定員1の枠を埋める
  def fill_slot
    credit = create_credit_for(create(:student), Date.new(2026, 11, 3))
    create(:makeup_reservation, makeup_credit: credit, makeup_slot: makeup_slot)
  end

  it "振替権が付くとき：期限・受講できる期間・予約できる枠を返す" do
    expect(choices).to be_eligible
    expect(choices.expires_on).to eq Date.new(2026, 12, 11)
    expect(choices.period).to eq Date.new(2026, 11, 12)..Date.new(2026, 12, 11)
    expect(choices.slots).to eq [ makeup_slot ]
    expect(choices.reason_counts).to eq({})
  end

  it "予約できる枠がないときは、理由ごとの枠の数を返す" do
    fill_slot # 定員1が埋まる

    expect(choices.slots).to be_empty
    expect(choices.reason_counts).to eq(full: 1)
  end

  describe "#problem_with" do
    it "確定できるなら nil" do
      expect(choices.problem_with(makeup_slot)).to be_nil
    end

    it "振替権が付かなくなっていたら :no_credit" do
      travel_to Time.zone.local(2026, 11, 11, 14, 0, 1) # 締切（2時間前）を過ぎる

      expect(choices.problem_with(makeup_slot)).to eq :no_credit
    end

    it "枠が埋まっていたら、その理由（:full）" do
      fill_slot

      expect(choices.problem_with(makeup_slot)).to eq :full
    end
  end
end
