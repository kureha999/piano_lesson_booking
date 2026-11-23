require "rails_helper"

RSpec.describe LessonSchedule do
  let(:student) { create(:student) }

  def dates(lessons)
    lessons.map(&:date)
  end

  describe "今日から2週間分" do
    it "水曜 16:00〜16:30 の枠なら、2回分の日付・開始日時・終了日時を返す" do
      travel_to Time.zone.local(2026, 6, 10, 12, 0) do # 2026-06-10 は水曜日
        create(:lesson_slot, student: student, wday: 3, start_time: "16:00", end_time: "16:30", starts_on: Date.new(2026, 4, 1))

        lessons = described_class.for(student, Date.current..(Date.current + 13)).lessons

        expect(lessons.map { |l| [ l.date, l.starts_at, l.ends_at ] }).to eq [
          [ Date.new(2026, 6, 10), Time.zone.local(2026, 6, 10, 16, 0), Time.zone.local(2026, 6, 10, 16, 30) ],
          [ Date.new(2026, 6, 17), Time.zone.local(2026, 6, 17, 16, 0), Time.zone.local(2026, 6, 17, 16, 30) ]
        ]
      end
    end

    it "日時は日本時間で返す" do
      travel_to Time.zone.local(2026, 6, 10, 12, 0) do
        create(:lesson_slot, student: student, wday: 3, start_time: "09:00", end_time: "09:30")

        lesson = described_class.for(student, Date.current..Date.current).lessons.sole

        expect(lesson.starts_at.zone).to eq "JST"
        expect(lesson.starts_at.utc).to eq Time.utc(2026, 6, 10, 0, 0)
      end
    end

    it "週に2回の枠と、別の曜日の枠があれば、開始日時の順に並べる" do
      create(:lesson_slot, student: student, wday: 6, start_time: "10:00", end_time: "10:30")
      create(:lesson_slot, student: student, wday: 3, start_time: "17:00", end_time: "17:30")
      create(:lesson_slot, student: student, wday: 3, start_time: "16:00", end_time: "16:30")

      lessons = described_class.for(student, Date.new(2026, 6, 8)..Date.new(2026, 6, 14)).lessons # 月〜日

      expect(lessons.map { |l| [ l.date, l.lesson_slot.time_range ] }).to eq [
        [ Date.new(2026, 6, 10), "16:00〜16:30" ], [ Date.new(2026, 6, 10), "17:00〜17:30" ], [ Date.new(2026, 6, 13), "10:00〜10:30" ]
      ]
    end
  end

  describe "期間の端" do
    let!(:slot) { create(:lesson_slot, student: student, wday: 3, starts_on: Date.new(2026, 1, 1)) } # 水曜

    it "期間の最初の日・最後の日が、枠の曜日なら含める" do
      lessons = described_class.new([ slot ], Date.new(2026, 6, 10)..Date.new(2026, 6, 24)).lessons

      expect(dates(lessons)).to eq [ Date.new(2026, 6, 10), Date.new(2026, 6, 17), Date.new(2026, 6, 24) ]
    end

    it "枠の曜日が期間にないときは、空になる" do
      expect(described_class.new([ slot ], Date.new(2026, 6, 11)..Date.new(2026, 6, 16)).lessons).to be_empty
    end

    it "1日だけの期間も計算できる" do
      expect(dates(described_class.new([ slot ], Date.new(2026, 6, 10)..Date.new(2026, 6, 10)).lessons)).to eq [ Date.new(2026, 6, 10) ]
      expect(described_class.new([ slot ], Date.new(2026, 6, 9)..Date.new(2026, 6, 9)).lessons).to be_empty
    end

    it "月をまたぐ期間も、7日ごとに計算する" do
      lessons = described_class.new([ slot ], Date.new(2026, 6, 24)..Date.new(2026, 7, 8)).lessons

      expect(dates(lessons)).to eq [ Date.new(2026, 6, 24), Date.new(2026, 7, 1), Date.new(2026, 7, 8) ]
    end

    it "年をまたぐ期間も計算できる" do
      lessons = described_class.new([ slot ], Date.new(2026, 12, 25)..Date.new(2027, 1, 8)).lessons

      expect(dates(lessons)).to eq [ Date.new(2026, 12, 30), Date.new(2027, 1, 6) ]
    end

    it "うるう日を含む期間も計算できる" do
      lessons = described_class.new([ slot ], Date.new(2028, 2, 23)..Date.new(2028, 3, 8)).lessons # 2028-02-23 は水曜

      expect(dates(lessons)).to eq [ Date.new(2028, 2, 23), Date.new(2028, 3, 1), Date.new(2028, 3, 8) ]
    end
  end

  describe "適用期間" do
    it "適用開始日より前の日は含めない（開始日当日は含める）" do
      slot = create(:lesson_slot, student: student, wday: 3, starts_on: Date.new(2026, 6, 17))

      lessons = described_class.new([ slot ], Date.new(2026, 6, 1)..Date.new(2026, 6, 30)).lessons

      expect(dates(lessons)).to eq [ Date.new(2026, 6, 17), Date.new(2026, 6, 24) ]
    end

    it "適用終了日より後の日は含めない（終了日当日は含める）" do
      slot = create(:lesson_slot, student: student, wday: 3, starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 6, 17))

      lessons = described_class.new([ slot ], Date.new(2026, 6, 1)..Date.new(2026, 6, 30)).lessons

      expect(dates(lessons)).to eq [ Date.new(2026, 6, 3), Date.new(2026, 6, 10), Date.new(2026, 6, 17) ]
    end

    it "適用期間が期間の外なら、空になる" do
      slot = create(:lesson_slot, student: student, wday: 3, starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 3, 31))

      expect(described_class.new([ slot ], Date.new(2026, 6, 1)..Date.new(2026, 6, 30)).lessons).to be_empty
    end

    it "適用開始日と適用終了日が同じ（1日だけの枠）なら、その日が枠の曜日のときだけ含める" do
      slot = create(:lesson_slot, student: student, wday: 3, starts_on: Date.new(2026, 6, 10), ends_on: Date.new(2026, 6, 10))

      expect(dates(described_class.new([ slot ], Date.new(2026, 6, 1)..Date.new(2026, 6, 30)).lessons)).to eq [ Date.new(2026, 6, 10) ]
    end

    it "枠を変更した（今の枠を終了して、新しい枠を作った）ときは、境目で古い枠と新しい枠に切り替わる" do
      old = create(:lesson_slot, student: student, wday: 3, start_time: "16:00", end_time: "16:30", starts_on: Date.new(2026, 4, 1))
      LessonSlotForm.for(old).tap do |form|
        form.wday = 4
        form.start_time = "17:00"
        form.end_time = "17:30"
        form.starts_on = Date.new(2026, 6, 15)
        form.save
      end

      lessons = described_class.for(student, Date.new(2026, 6, 8)..Date.new(2026, 6, 21)).lessons

      expect(lessons.map { |l| [ l.date, l.lesson_slot.wday_name, l.lesson_slot.time_range ] }).to eq [
        [ Date.new(2026, 6, 10), "水曜日", "16:00〜16:30" ], [ Date.new(2026, 6, 18), "木曜日", "17:00〜17:30" ]
      ]
    end
  end

  describe "生徒" do
    it "指定した生徒の固定枠だけを対象にする" do
      other = create(:student)
      create(:lesson_slot, student: student, wday: 3)
      create(:lesson_slot, student: other, wday: 4, start_time: "17:00", end_time: "17:30")

      lessons = described_class.for(student, Date.new(2026, 6, 8)..Date.new(2026, 6, 14)).lessons

      expect(lessons.map(&:student)).to eq [ student ]
    end

    it "固定枠がない生徒は、空になる" do
      expect(described_class.for(student, Date.new(2026, 6, 8)..Date.new(2026, 6, 14)).lessons).to be_empty
    end

    it "兄弟など、複数の生徒の固定枠をまとめて渡せる" do
      sibling = create(:student, guardian: student.guardian)
      create(:lesson_slot, student: student, wday: 3, start_time: "16:00", end_time: "16:30")
      create(:lesson_slot, student: sibling, wday: 3, start_time: "16:30", end_time: "17:00")

      lessons = described_class.new(LessonSlot.where(student: [ student, sibling ]).includes(:student), Date.new(2026, 6, 10)..Date.new(2026, 6, 10)).lessons

      expect(lessons.map(&:student)).to eq [ student, sibling ]
    end
  end

  describe "欠席との組み合わせ" do
    it "key（固定枠の ID と日付）で、欠席の (lesson_slot_id, lesson_on) と照合できる" do
      slot = create(:lesson_slot, student: student, wday: 3)
      absent_keys = [ [ slot.id, Date.new(2026, 6, 17) ] ].to_set

      lessons = described_class.for(student, Date.new(2026, 6, 10)..Date.new(2026, 6, 24)).lessons

      expect(lessons.map { |lesson| [ lesson.date, absent_keys.include?(lesson.key) ] }).to eq [
        [ Date.new(2026, 6, 10), false ], [ Date.new(2026, 6, 17), true ], [ Date.new(2026, 6, 24), false ]
      ]
    end
  end
end
