require "rails_helper"

RSpec.describe ConfirmAbsence do
  # 2026年11月2日（月）の朝。欠席するのは、水曜日 16:00〜16:30 のレッスン（11/11）
  let(:now) { Time.zone.local(2026, 11, 2, 9, 0) }
  let(:student) { create(:student) }
  let(:guardian) { student.guardian }
  let(:lesson_slot) { create(:lesson_slot, student: student, wday: 3, start_time: "16:00", end_time: "16:30") }
  let(:lesson_on) { Date.new(2026, 11, 11) }
  let(:makeup_slot) { create_makeup_slot(Date.new(2026, 11, 16)) }

  before { travel_to now }

  def confirm(slot = makeup_slot, on: lesson_on, by: guardian)
    described_class.call(lesson_slot: lesson_slot, lesson_on: on, reported_by: by, makeup_slot: slot)
  end

  def counts
    [ Absence.count, MakeupCredit.count, MakeupReservation.count ]
  end

  describe "欠席する → 枠を選ぶ → 確定する" do
    it "欠席・振替権・振替予約を、まとめて作る" do
      result = confirm

      expect(result).to be_success
      expect(result.reason).to be_nil
      expect(counts).to eq [ 1, 1, 1 ]
      expect(result.absence).to have_attributes(lesson_slot: lesson_slot, lesson_on: lesson_on, reported_by: guardian, no_credit_reason: nil)
      expect(result.makeup_credit).to have_attributes(student: student, expires_on: Date.new(2026, 12, 11))
      expect(result.reservation).to have_attributes(makeup_slot: makeup_slot, student: student, makeup_credit: result.makeup_credit, canceled_at: nil)
    end

    it "振替を後で選ぶ（枠なし）なら、欠席と振替権だけを作る。振替権は未使用で残る" do
      result = confirm(nil)

      expect(result).to be_success
      expect(counts).to eq [ 1, 1, 0 ]
      expect(result.reservation).to be_nil
      expect(result.makeup_credit.status).to eq :unused
    end

    it "振替権が付かない欠席（締切後）は、欠席だけを作り、理由を残す" do
      travel_to Time.zone.local(2026, 11, 11, 14, 1)

      result = confirm(nil)

      expect(result).to be_success
      expect(counts).to eq [ 1, 0, 0 ]
      expect(result.absence).to be_after_deadline
    end
  end

  describe "失敗したときは、何も登録しない（欠席だけが登録されることはない）" do
    it "選んだ枠が先に埋まっていたら、:full で失敗し、欠席も振替権も作らない" do
      other = create_credit_for(create(:student), Date.new(2026, 11, 9))
      create(:makeup_reservation, makeup_slot: makeup_slot, makeup_credit: other)
      before_counts = counts

      result = confirm

      expect(result).not_to be_success
      expect(result.reason).to eq :full
      expect(counts).to eq before_counts
    end

    it "選んだ枠がルール外（期限後）なら、その理由で失敗し、何も作らない" do
      too_late = create_makeup_slot(Date.new(2026, 12, 12))

      result = confirm(too_late)

      expect(result.reason).to eq :out_of_period
      expect(counts).to eq [ 0, 0, 0 ]
    end

    it "確定の時点で振替権が付かなくなっていたら、:no_credit で失敗し、何も作らない" do
      makeup_slot
      travel_to Time.zone.local(2026, 11, 11, 14, 1) # 締切の後。振替枠 11/16 は期間内

      result = confirm

      expect(result.reason).to eq :no_credit
      expect(counts).to eq [ 0, 0, 0 ]
    end

    it "すでに欠席を連絡したレッスンは、:invalid で失敗し、何も増えない" do
      confirm(nil)

      result = confirm

      expect(result.reason).to eq :invalid
      expect(result.absence.errors[:lesson_on]).to include "のレッスンは、すでに欠席を連絡しています"
      expect(counts).to eq [ 1, 1, 0 ]
    end

    it "予約の途中で想定外のエラーが起きても、欠席と振替権を残さない（1つのトランザクション）" do
      makeup_slot
      allow(MakeupReservation).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "想定外のエラー")

      expect { confirm }.to raise_error(ActiveRecord::StatementInvalid)
      expect(counts).to eq [ 0, 0, 0 ]
    end
  end

  describe "同時に確定したとき" do
    # 実際に複数のスレッドから確定する。トランザクションをまたぐので、テストごとのロールバックは使わず、終わったら消す
    context "複数のスレッドから確定する" do
      self.use_transactional_tests = false

      after do
        [ MakeupReservation, MakeupCredit, Absence, LessonSlot, Student, MakeupSlot, MakeupRule ].each(&:delete_all)
        User.delete_all
      end

      # 2人の生徒（月曜日・火曜日のレッスン）が、同じ枠を選んで同時に確定する
      def confirm_concurrently(slot_id)
        targets = [ [ Date.new(2026, 11, 9), 1 ], [ Date.new(2026, 11, 10), 2 ] ].map do |on, wday|
          kid = create(:student)
          [ create(:lesson_slot, student: kid, wday: wday, start_time: "16:00", end_time: "16:30"), on, kid.guardian ]
        end
        targets.map do |slot, on, user|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              described_class.call(lesson_slot: LessonSlot.find(slot.id), lesson_on: on, reported_by: user, makeup_slot: MakeupSlot.find(slot_id))
            end
          end
        end.map(&:value)
      end

      it "定員1の枠を2人が同時に選んでも、確定できるのは1人だけ。負けた方は、欠席も登録されない" do
        slot_id = makeup_slot.id
        # 確認と保存の間に待ちを入れて、ロックがなければ両方が成功する状況にする
        allow_any_instance_of(MakeupSlotAvailability).to receive(:unavailable_reason).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
          original.call(*args).tap { sleep 0.2 }
        end

        results = confirm_concurrently(slot_id)

        expect(results.count(&:success?)).to eq 1
        expect(results.reject(&:success?).map(&:reason)).to eq [ :full ]
        expect(counts).to eq [ 1, 1, 1 ]
      end
    end
  end
end
