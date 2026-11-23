require "rails_helper"

RSpec.describe MakeupSlotAvailability do
  # 2026年11月2日（月）の朝。欠席は水曜日（11/11）の16:00のレッスンで、振替の期限は12/11
  let(:now) { Time.zone.local(2026, 11, 2, 9, 0) }
  let(:student) { create(:student) }
  let(:availability) { described_class.new(credit) }
  let(:credit) { create_credit_for(student, Date.new(2026, 11, 11)) }

  # 時刻を合わせた後に、振替権を作る（欠席は、レッスンが始まる前でないと登録できない）
  before do
    travel_to now
    credit
  end

  # 呼ぶたびに作り直す（時刻を動かした後の「いま」で判定するため）
  def reason_of(slot, availability: described_class.new(credit))
    availability.unavailable_reason(slot)
  end

  describe "#unavailable_reason_counts" do
    it "予約できない理由ごとに、まだ終わっていない枠の数を返す（予約できる枠は数えない）" do
      create_makeup_slot(Date.new(2026, 11, 16)) # 予約できる
      create_makeup_slot(Date.new(2026, 12, 12)) # 期限より後
      create_makeup_slot(Date.new(2026, 12, 14)) # 期限より後
      full = create_makeup_slot(Date.new(2026, 11, 17))
      create(:makeup_reservation, makeup_slot: full, makeup_credit: create_credit_for(create(:student), Date.new(2026, 11, 9)))

      expect(availability.unavailable_reason_counts).to eq(out_of_period: 2, full: 1)
    end

    it "枠がなければ、空" do
      expect(availability.unavailable_reason_counts).to eq({})
    end
  end

  describe "予約できる枠" do
    it "期限内で、締切前で、定員に空きがあり、重ならない枠は予約できる" do
      slot = create_makeup_slot(Date.new(2026, 11, 16))

      expect(reason_of(slot)).to be_nil
      expect(availability.slots).to eq [ slot ]
    end

    it "開始日時の順に返す" do
      later = create_makeup_slot(Date.new(2026, 11, 20))
      earlier = create_makeup_slot(Date.new(2026, 11, 16))

      expect(availability.slots).to eq [ earlier, later ]
    end

    it "予約できない枠は、一覧に含めない" do
      ok = create_makeup_slot(Date.new(2026, 11, 16))
      create_makeup_slot(Date.new(2027, 1, 18)) # 期限より後

      expect(availability.slots).to eq [ ok ]
    end
  end

  describe "振替の期限（受講日で判定する）" do
    it "欠席日の翌日から、期限（欠席日の30日後）までの枠は予約できる（両端を含む）" do
      first_day = create_makeup_slot(Date.new(2026, 11, 12))
      last_day = create_makeup_slot(Date.new(2026, 12, 11))

      expect(reason_of(first_day)).to be_nil
      expect(reason_of(last_day)).to be_nil
    end

    it "欠席日と同じ日の枠は、予約できない（欠席日より前の振替は先取りできない）" do
      same_day = create_makeup_slot(Date.new(2026, 11, 11), 10)

      expect(reason_of(same_day)).to eq :out_of_period
    end

    it "期限の翌日の枠は、予約できない" do
      expect(reason_of(create_makeup_slot(Date.new(2026, 12, 12)))).to eq :out_of_period
    end

    it "11月10日（火）の欠席なら、12月10日までに受講する枠だけ予約できる（README 12-2 の例）" do
      tuesday_credit = create_credit_for(create(:student), Date.new(2026, 11, 10))
      tuesday = described_class.new(tuesday_credit)

      expect(reason_of(create_makeup_slot(Date.new(2026, 12, 10)), availability: tuesday)).to be_nil
      expect(reason_of(create_makeup_slot(Date.new(2026, 12, 11)), availability: tuesday)).to eq :out_of_period
    end

    it "予約する日ではなく、受講する日で判定する（期限の前日に予約しても、受講日が期限後なら予約できない）" do
      travel_to Time.zone.local(2026, 12, 10, 9, 0)

      expect(reason_of(create_makeup_slot(Date.new(2026, 12, 12)))).to eq :out_of_period
    end

    it "期限は、振替権を作ったときのルールで決まる。あとからルールを変えても変わらない" do
      MakeupRule.current.update!(valid_days: 7)

      expect(reason_of(create_makeup_slot(Date.new(2026, 12, 11)))).to be_nil
    end
  end

  describe "振替予約の締切（枠の前日の23:59）" do
    let(:slot) { create_makeup_slot(Date.new(2026, 11, 16)) } # 月曜日 10:00

    it "前日の23:59までは予約できる" do
      travel_to Time.zone.local(2026, 11, 15, 23, 59)

      expect(reason_of(slot)).to be_nil
    end

    it "当日の0:00になると、予約できない" do
      travel_to Time.zone.local(2026, 11, 16, 0, 0)

      expect(reason_of(slot)).to eq :deadline_passed
    end

    it "日本時間で判定する（UTC の 11/15 14:59 は、日本時間の 23:59）" do
      travel_to Time.utc(2026, 11, 15, 14, 59)
      expect(reason_of(slot)).to be_nil

      travel_to Time.utc(2026, 11, 15, 15, 0)
      expect(reason_of(slot)).to eq :deadline_passed
    end

    it "締切の日数は、ルールの設定に従う（2日前なら、2日前の23:59まで）" do
      MakeupRule.current.update!(reservation_deadline_days: 2)

      travel_to Time.zone.local(2026, 11, 14, 23, 59)
      expect(reason_of(slot)).to be_nil

      travel_to Time.zone.local(2026, 11, 15, 0, 0)
      expect(reason_of(slot)).to eq :deadline_passed
    end

    it "すでに始まった枠は、予約できない" do
      travel_to Time.zone.local(2026, 11, 16, 10, 0)

      expect(reason_of(slot)).to eq :already_started
    end
  end

  describe "枠の定員（先着順）" do
    let(:slot) { create_makeup_slot(Date.new(2026, 11, 16), capacity: 1) }

    it "定員に達した枠は、予約できない" do
      create(:makeup_reservation, makeup_slot: slot, makeup_credit: create_credit_for(create(:student), Date.new(2026, 11, 9)))

      expect(reason_of(slot)).to eq :full
      expect(availability.slots).to be_empty
    end

    it "定員に空きがあれば、予約できる（定員2で1人予約済み）" do
      slot = create_makeup_slot(Date.new(2026, 11, 17), capacity: 2)
      create(:makeup_reservation, makeup_slot: slot, makeup_credit: create_credit_for(create(:student), Date.new(2026, 11, 9)))

      expect(reason_of(slot)).to be_nil
    end

    it "キャンセルした予約は、定員に数えない" do
      create(:makeup_reservation, :canceled, makeup_slot: slot, makeup_credit: create_credit_for(create(:student), Date.new(2026, 11, 9)))

      expect(reason_of(slot)).to be_nil
    end
  end

  describe "時間の重複の防止" do
    it "その生徒の固定レッスンと時間が重なる枠は、予約できない" do
      slot = create_makeup_slot(Date.new(2026, 11, 19), 10) # 木曜日 10:00〜10:30
      create(:lesson_slot, student: student, wday: 4, start_time: "10:15", end_time: "10:45") # 枠を作った後に、重なる固定枠を作る

      expect(reason_of(slot)).to eq :conflict
    end

    it "固定レッスンと接しているだけ（終了と開始が同じ）なら、予約できる" do
      slot = create_makeup_slot(Date.new(2026, 11, 19), 10)
      create(:lesson_slot, student: student, wday: 4, start_time: "10:30", end_time: "11:00")

      expect(reason_of(slot)).to be_nil
    end

    it "ほかの生徒の固定レッスンとは、重ならないものとして扱う" do
      slot = create_makeup_slot(Date.new(2026, 11, 19), 10)
      create(:lesson_slot, student: create(:student), wday: 4, start_time: "10:00", end_time: "10:30")

      expect(reason_of(slot)).to be_nil
    end

    it "欠席するレッスンは、受けないので、重なりに数えない" do
      slot = create_makeup_slot(Date.new(2026, 11, 19), 10)
      thursday = create(:lesson_slot, student: student, wday: 4, start_time: "10:00", end_time: "10:30")
      create(:absence, lesson_slot: thursday, lesson_on: Date.new(2026, 11, 19))

      expect(reason_of(slot)).to be_nil
    end

    it "その生徒のほかの有効な振替予約と時間が重なる枠は、予約できない" do
      reserved = create_makeup_slot(Date.new(2026, 11, 16), 10)
      create(:makeup_reservation, makeup_slot: reserved, makeup_credit: credit)
      other_credit = create_credit_for(student, Date.new(2026, 11, 4)) # 水曜日の別の回（期間に 11/16 を含む）
      # 振替枠どうしは DB の排他制約で重ならないので、保存しない枠で確かめる
      overlapping = MakeupSlot.new(starts_at: reserved.starts_at + 15.minutes, ends_at: reserved.ends_at + 15.minutes, capacity: 1)

      expect(described_class.new(other_credit).unavailable_reason(overlapping)).to eq :conflict
    end

    it "キャンセルした振替予約とは、重なりに数えない" do
      reserved = create_makeup_slot(Date.new(2026, 11, 16), 10)
      create(:makeup_reservation, :canceled, makeup_slot: reserved, makeup_credit: credit)
      overlapping = MakeupSlot.new(starts_at: reserved.starts_at + 15.minutes, ends_at: reserved.ends_at + 15.minutes, capacity: 1)

      expect(reason_of(overlapping)).to be_nil
    end
  end

  describe "振替権がすでに使われているとき" do
    it "有効な予約がある振替権は、どの枠も予約できない（再振替はできない）" do
      create(:makeup_reservation, makeup_credit: credit, makeup_slot: create_makeup_slot(Date.new(2026, 11, 16)))
      other = create_makeup_slot(Date.new(2026, 11, 17))

      expect(reason_of(other)).to eq :credit_used
      expect(availability.slots).to be_empty
    end

    it "予約をキャンセルすると、また予約できる" do
      create(:makeup_reservation, :canceled, makeup_credit: credit, makeup_slot: create_makeup_slot(Date.new(2026, 11, 16)))
      other = create_makeup_slot(Date.new(2026, 11, 17))

      expect(reason_of(other)).to be_nil
    end
  end
end
