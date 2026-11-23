require "rails_helper"

RSpec.describe WeeklyAgenda do
  # 2026年11月9日（月）〜15日（日）が今週
  let(:monday) { Time.zone.local(2026, 11, 9, 8, 0) }
  let(:student) { create(:student, name: "ひなた") }

  # 生徒の、その日の曜日の固定枠（16:00〜16:30）で欠席する。固定枠は先生が1人なので、生徒ごとに曜日を変えて使う
  def absence_on(date, *traits, kid: student)
    slot = kid.lesson_slots.find_by(wday: date.wday) || create(:lesson_slot, student: kid, wday: date.wday, start_time: "16:00", end_time: "16:30")
    create(:absence, *traits, lesson_slot: slot, lesson_on: date, reported_by: kid.guardian)
  end

  describe "#week" do
    it "今週は、月曜日〜日曜日（日本時間）" do
      expect(described_class.new(now: Time.zone.local(2026, 11, 9, 0, 0)).week).to eq Date.new(2026, 11, 9)..Date.new(2026, 11, 15)
      expect(described_class.new(now: Time.zone.local(2026, 11, 15, 23, 59)).week).to eq Date.new(2026, 11, 9)..Date.new(2026, 11, 15)
      expect(described_class.new(now: Time.zone.local(2026, 11, 16, 0, 0)).week).to eq Date.new(2026, 11, 16)..Date.new(2026, 11, 22)
    end

    it "日本時間で判定する（UTC の日曜 15:00 は、日本時間の月曜 0:00）" do
      expect(described_class.new(now: Time.utc(2026, 11, 8, 15, 0)).week.begin).to eq Date.new(2026, 11, 9)
      expect(described_class.new(now: Time.utc(2026, 11, 8, 14, 59)).week.begin).to eq Date.new(2026, 11, 2)
    end
  end

  describe "#entries" do
    before { travel_to monday }

    it "今週の欠席と振替予約を、開始日時の順に並べる" do
      later_absence = absence_on(Date.new(2026, 11, 13)) # 金曜日
      credit = create(:makeup_credit, absence: absence_on(Date.new(2026, 11, 11)))
      create(:makeup_reservation, makeup_credit: credit, makeup_slot: create_makeup_slot(Date.new(2026, 11, 12), 10)) # 木曜日 10:00

      entries = described_class.new.entries

      expect(entries.map { |entry| [ entry.kind, entry.starts_at.strftime("%-m/%-d %H:%M") ] }).to eq [
        [ :absence, "11/11 16:00" ], [ :makeup, "11/12 10:00" ], [ :absence, "11/13 16:00" ]
      ]
      expect(entries.last.absence).to eq later_absence
    end

    it "欠席の終了日時は、固定枠の長さから計算する" do
      absence_on(Date.new(2026, 11, 11))

      entry = described_class.new.entries.first

      expect(entry.ends_at - entry.starts_at).to eq 30.minutes
    end

    it "月曜日・日曜日の境目：今週の月曜日 0:00 から日曜日 23:59 までを含み、前後の週は含めない" do
      absence_on(Date.new(2026, 11, 9)) # 今週の月曜日
      absence_on(Date.new(2026, 11, 15)) # 今週の日曜日
      absence_on(Date.new(2026, 11, 16)) # 来週の月曜日
      create(:makeup_reservation, makeup_credit: create(:makeup_credit, absence: absence_on(Date.new(2026, 11, 10))),
        makeup_slot: create_makeup_slot(Date.new(2026, 11, 15), 23, 0)) # 日曜日 23:00〜23:30（今週）
      create(:makeup_reservation, makeup_credit: create(:makeup_credit, absence: absence_on(Date.new(2026, 11, 12))),
        makeup_slot: create_makeup_slot(Date.new(2026, 11, 16), 0, 0)) # 月曜日 0:00（来週）

      days = described_class.new.entries.map { |entry| entry.starts_at.strftime("%-m/%-d") }

      expect(days).to eq %w[11/9 11/10 11/12 11/15 11/15] # 11/16（来週）の欠席と、11/16 0:00 の振替は含まない
    end

    it "先週の欠席は含めない" do
      travel_to Time.zone.local(2026, 11, 1, 8, 0)
      absence_on(Date.new(2026, 11, 8)) # 日曜日（先週）
      travel_to monday

      expect(described_class.new.entries).to be_empty
    end

    it "キャンセルした振替予約は含めない" do
      credit = create(:makeup_credit, absence: absence_on(Date.new(2026, 11, 10)))
      create(:makeup_reservation, :canceled, makeup_credit: credit, makeup_slot: create_makeup_slot(Date.new(2026, 11, 12)))

      expect(described_class.new.entries.map(&:kind)).to eq [ :absence ]
    end

    it "締切後の欠席は「当日欠席」、月の上限を超えた欠席はそれと分かる" do
      absence_on(Date.new(2026, 11, 10), :after_deadline)
      absence_on(Date.new(2026, 11, 11), :over_monthly_limit)
      absence_on(Date.new(2026, 11, 12))

      same_day, over_limit, normal = described_class.new.entries

      expect([ same_day.same_day_absence?, same_day.over_limit_absence? ]).to eq [ true, false ]
      expect([ over_limit.same_day_absence?, over_limit.over_limit_absence? ]).to eq [ false, true ]
      expect([ normal.same_day_absence?, normal.over_limit_absence? ]).to eq [ false, false ]
    end

    it "欠席の振替予約（Entry#makeup_reservation）を返す。予約していなければ nil" do
      reserved = create(:makeup_credit, absence: absence_on(Date.new(2026, 11, 10)))
      reservation = create(:makeup_reservation, makeup_credit: reserved, makeup_slot: create_makeup_slot(Date.new(2026, 11, 20)))
      absence_on(Date.new(2026, 11, 11))

      first, second = described_class.new.entries

      expect(first.makeup_reservation).to eq reservation
      expect(second.makeup_reservation).to be_nil
    end

    it "兄弟など、複数の生徒の分をまとめて返す（生徒と保護者の名前つき）" do
      other = create(:student, name: "そうた", guardian: create(:guardian, name: "鈴木一郎"))
      absence_on(Date.new(2026, 11, 10))
      absence_on(Date.new(2026, 11, 11), kid: other)

      entries = described_class.new.entries

      expect(entries.map { |entry| [ entry.student.name, entry.guardian.name ] }).to eq [ [ "ひなた", "保護者" ], [ "そうた", "鈴木一郎" ] ]
    end
  end
end
