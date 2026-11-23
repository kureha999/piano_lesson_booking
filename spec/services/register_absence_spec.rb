require "rails_helper"

RSpec.describe RegisterAbsence do
  # 水曜日 16:00〜16:30 の固定枠。2026年11月の水曜日は 4・11・18・25 日
  let(:student) { create(:student) }
  let(:guardian) { student.guardian }
  let(:slot) { create(:lesson_slot, student: student, wday: 3, start_time: "16:00", end_time: "16:30") }
  let(:now) { Time.zone.local(2026, 11, 1, 9, 0) }

  def register(lesson_on, lesson_slot: slot)
    described_class.call(lesson_slot: lesson_slot, lesson_on: lesson_on, reported_by: guardian)
  end

  before { travel_to now }

  describe "振替権が付く条件（欠席連絡の締切）" do
    let(:lesson_day) { Date.new(2026, 11, 11) } # 水曜日 16:00 開始。初期値の締切は 14:00

    it "締切より前に連絡すると、振替権が付く" do
      travel_to(Time.zone.local(2026, 11, 11, 9, 0)) do
        result = register(lesson_day)

        expect(result).to be_success
        expect(result.makeup_credit).to be_persisted
        expect(result.absence.no_credit_reason).to be_nil
      end
    end

    it "締切ちょうど（14:00）までは、振替権が付く" do
      travel_to(Time.zone.local(2026, 11, 11, 14, 0, 0)) do
        expect(register(lesson_day).makeup_credit).to be_present
      end
    end

    it "締切を1秒でも過ぎると、振替権は付かず、理由は「締切後」になる" do
      travel_to(Time.zone.local(2026, 11, 11, 14, 0, 1)) do
        result = register(lesson_day)

        expect(result).to be_success
        expect(result.makeup_credit).to be_nil
        expect(result.absence).to be_after_deadline
      end
    end

    it "前日までに連絡しても、振替権が付く" do
      travel_to(Time.zone.local(2026, 11, 10, 23, 59)) do
        expect(register(lesson_day).makeup_credit).to be_present
      end
    end

    it "レッスン開始の後は、欠席を登録できない" do
      travel_to(Time.zone.local(2026, 11, 11, 16, 0)) do
        result = register(lesson_day)

        expect(result).not_to be_success
        expect(result.makeup_credit).to be_nil
        expect(result.absence.errors[:lesson_on]).to include "のレッスンはすでに始まっています"
      end
    end

    it "日本時間で判定する（UTC の 05:00 は、日本時間の 14:00）" do
      travel_to(Time.utc(2026, 11, 11, 5, 0)) do
        expect(register(lesson_day).makeup_credit).to be_present
      end
    end

    it "締切の時間は、ルールの設定に従う（開始の4時間前なら、12:00 まで）" do
      MakeupRule.current.update!(absence_deadline_hours: 4)

      travel_to(Time.zone.local(2026, 11, 11, 12, 0))
      expect(register(Date.new(2026, 11, 11)).makeup_credit).to be_present
      travel_to(Time.zone.local(2026, 11, 18, 12, 1))
      expect(register(Date.new(2026, 11, 18)).absence).to be_after_deadline
    end
  end

  describe "月の上限" do
    it "11月に3回欠席すると、3回目は振替権が付かず、理由は「月の上限」になる（README 12-2 の例）" do
      first = register(Date.new(2026, 11, 4))
      second = register(Date.new(2026, 11, 11))
      third = register(Date.new(2026, 11, 18))

      expect([ first, second ].map(&:makeup_credit)).to all(be_present)
      expect(third).to be_success
      expect(third.makeup_credit).to be_nil
      expect(third.absence).to be_over_monthly_limit
    end

    it "上限に達していても、欠席は登録できる" do
      register(Date.new(2026, 11, 4))
      register(Date.new(2026, 11, 11))

      expect { register(Date.new(2026, 11, 18)) }.to change(Absence, :count).by(1).and not_change(MakeupCredit, :count)
    end

    it "月の上限は、ルールの設定に従う（上限0なら、1回目から付かない）" do
      MakeupRule.current.update!(monthly_limit: 0)

      expect(register(Date.new(2026, 11, 4)).absence).to be_over_monthly_limit
    end

    it "月は欠席日で数える。連絡した日の月ではない" do
      # 11月1日に、12月の欠席を2回連絡しても、11月の分には数えない
      register(Date.new(2026, 12, 2))
      register(Date.new(2026, 12, 9))

      expect(register(Date.new(2026, 11, 4)).makeup_credit).to be_present
    end

    it "締切後の欠席（振替権が付かない）は、月の上限の回数に数えない" do
      travel_to(Time.zone.local(2026, 11, 4, 15, 0))
      expect(register(Date.new(2026, 11, 4)).absence).to be_after_deadline

      expect(register(Date.new(2026, 11, 11)).makeup_credit).to be_present
      expect(register(Date.new(2026, 11, 18)).makeup_credit).to be_present
      expect(register(Date.new(2026, 11, 25)).absence).to be_over_monthly_limit
    end

    it "兄弟など、ほかの生徒の欠席は数えない（上限は生徒ごと）" do
      sibling_slot = create(:lesson_slot, student: create(:student, guardian: guardian), wday: 4, start_time: "16:00", end_time: "16:30")
      register(Date.new(2026, 11, 4))
      register(Date.new(2026, 11, 11))

      expect(register(Date.new(2026, 11, 5), lesson_slot: sibling_slot).makeup_credit).to be_present
    end

    context "月の境目" do
      let(:saturday_slot) { create(:lesson_slot, student: student, wday: 6, start_time: "10:00", end_time: "10:30") }
      let(:sunday_slot) { create(:lesson_slot, student: student, wday: 0, start_time: "10:00", end_time: "10:30") }
      let(:now) { Time.zone.local(2026, 10, 1, 9, 0) }

      it "月末（10/31）の欠席は、翌月（11/1）の上限に数えない" do
        register(Date.new(2026, 10, 31), lesson_slot: saturday_slot)
        register(Date.new(2026, 10, 28))

        # 11月分は、0回から数える（11/1 は日曜日、11/4 は水曜日）
        expect(register(Date.new(2026, 11, 1), lesson_slot: sunday_slot).makeup_credit).to be_present
        expect(register(Date.new(2026, 11, 4)).makeup_credit).to be_present
        expect(register(Date.new(2026, 11, 11)).absence).to be_over_monthly_limit
      end

      it "月初（11/1）の欠席は、前月（10月）の上限に数えない" do
        register(Date.new(2026, 11, 1), lesson_slot: sunday_slot)
        register(Date.new(2026, 11, 4))

        expect(register(Date.new(2026, 10, 31), lesson_slot: saturday_slot).makeup_credit).to be_present
        expect(register(Date.new(2026, 10, 28)).makeup_credit).to be_present
        expect(register(Date.new(2026, 10, 21)).absence).to be_over_monthly_limit
      end
    end
  end

  describe "振替の期限" do
    it "欠席日から30日後（初期値）を、expires_on に保存する（README 12-2：11月10日 → 12月10日）" do
      mon_slot = create(:lesson_slot, student: student, wday: 2, start_time: "16:00", end_time: "16:30") # 火曜日
      result = register(Date.new(2026, 11, 10), lesson_slot: mon_slot)

      expect(result.makeup_credit.expires_on).to eq Date.new(2026, 12, 10)
    end

    it "作成時のルールで計算する。後からルールを変えても、すでにある振替権は変わらない" do
      credit = register(Date.new(2026, 11, 4)).makeup_credit
      MakeupRule.current.update!(valid_days: 7)
      later = register(Date.new(2026, 11, 11)).makeup_credit

      expect(credit.reload.expires_on).to eq Date.new(2026, 12, 4)
      expect(later.expires_on).to eq Date.new(2026, 11, 18)
    end
  end

  describe "登録できない欠席" do
    it "固定枠の曜日でない日は、登録せず、振替権も付けない" do
      result = register(Date.new(2026, 11, 12)) # 木曜日

      expect(result).not_to be_success
      expect(result.absence.errors[:lesson_on]).to be_present
      expect(Absence.count).to eq 0
      expect(MakeupCredit.count).to eq 0
    end

    it "同じレッスンの欠席は、2回登録できない。2回目に振替権は付かない" do
      register(Date.new(2026, 11, 4))
      result = register(Date.new(2026, 11, 4))

      expect(result).not_to be_success
      expect(result.absence.errors[:lesson_on]).to include "のレッスンは、すでに欠席を連絡しています"
      expect(MakeupCredit.count).to eq 1
    end

    it "検証の後に同じ欠席が登録されても（DB の一意インデックス）、エラーとして返す" do
      register(Date.new(2026, 11, 4))
      allow_any_instance_of(Absence).to receive(:valid?).and_return(true) # rubocop:disable RSpec/AnyInstance

      result = register(Date.new(2026, 11, 4))

      expect(result).not_to be_success
      expect(result.absence.errors[:lesson_on]).to include "のレッスンは、すでに欠席を連絡しています"
    end
  end

  describe "同時に連絡したとき" do
    it "数える前に、生徒の行をロックする" do
      allow(student).to receive(:with_lock).and_call_original
      slot.student = student

      register(Date.new(2026, 11, 4))

      expect(student).to have_received(:with_lock)
    end

    # 実際に複数のスレッドから連絡する。トランザクションをまたぐので、テストごとのロールバックは使わず、終わったら消す
    context "複数のスレッドから連絡する" do
      self.use_transactional_tests = false

      after do
        [ MakeupCredit, Absence, LessonSlot, Student, MakeupRule ].each(&:delete_all)
        User.delete_all
      end

      it "同じ生徒が同時に4回連絡しても、振替権が付くのは月の上限（2回）までになる" do
        days = [ 4, 11, 18, 25 ].map { |day| Date.new(2026, 11, day) }
        slot_id = slot.id

        results = days.map do |day|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              described_class.call(lesson_slot: LessonSlot.find(slot_id), lesson_on: day, reported_by: guardian)
            end
          end
        end.map(&:value)

        expect(results).to all(be_success)
        expect(Absence.where(no_credit_reason: nil).count).to eq 2
        expect(MakeupCredit.count).to eq 2
        expect(Absence.over_monthly_limit.count).to eq 2
      end
    end
  end
end
