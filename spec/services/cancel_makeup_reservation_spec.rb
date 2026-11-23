require "rails_helper"

RSpec.describe CancelMakeupReservation do
  # 2026年11月2日（月）の朝。振替枠は 11/16（月）10:00〜10:30。予約の締切は、前日（11/15）の23:59まで
  let(:now) { Time.zone.local(2026, 11, 2, 9, 0) }
  let(:student) { create(:student) }
  let(:credit) { create_credit_for(student, Date.new(2026, 11, 11)) }
  let(:makeup_slot) { create_makeup_slot(Date.new(2026, 11, 16)) }
  let(:reservation) { create(:makeup_reservation, makeup_credit: credit, makeup_slot: makeup_slot) }

  before { travel_to now
reservation  }



  describe "締切前" do
    it "canceled_at に日時を入れる。行は消さない" do
      result = described_class.call(reservation)

      expect(result).to be_success
      expect(result.reason).to be_nil
      expect(reservation.reload.canceled_at).to eq now
      expect(reservation).to be_canceled
      expect(MakeupReservation.count).to eq 1
    end

    it "振替権は、未使用に戻る（予約済み → 未使用）" do
      expect { described_class.call(reservation) }.to change { credit.reload.status }.from(:reserved).to(:unused)
    end

    it "キャンセル後、同じ振替権でほかの枠を予約できる" do
      described_class.call(reservation)
      other = create_makeup_slot(Date.new(2026, 11, 18))

      result = ReserveMakeupSlot.call(makeup_credit: credit, makeup_slot: other)

      expect(result).to be_success
      expect(credit.reload.status).to eq :reserved
      expect(MakeupReservation.where(makeup_credit: credit).count).to eq 2
    end

    it "キャンセルした枠は、定員に空きが戻る" do
      expect { described_class.call(reservation) }.to change(makeup_slot, :reserved_count).from(1).to(0)
    end

    it "キャンセルした枠を、同じ振替権でもう一度予約できる" do
      described_class.call(reservation)

      expect(ReserveMakeupSlot.call(makeup_credit: credit, makeup_slot: makeup_slot)).to be_success
    end
  end

  describe "締切の境目（前日の23:59:59まで）" do
    it "締切ちょうど（11/15 23:59:59）まではキャンセルできる" do
      travel_to Time.zone.local(2026, 11, 15, 23, 59, 59)

      expect(described_class.call(reservation)).to be_success
    end

    it "締切を過ぎる（11/16 0:00）と、キャンセルできない。予約は有効のまま、振替権は予約済みのまま" do
      travel_to Time.zone.local(2026, 11, 16, 0, 0, 0)

      result = described_class.call(reservation)

      expect(result).not_to be_success
      expect(result.reason).to eq :deadline_passed
      expect(reservation.reload).to be_active
      expect(credit.reload.status).to eq :reserved
    end

    it "枠が始まった後は、キャンセルできない（使用済みのまま）" do
      travel_to Time.zone.local(2026, 11, 16, 10, 30)

      expect(described_class.call(reservation).reason).to eq :deadline_passed
      expect(credit.reload.status).to eq :used
    end

    it "日本時間で判定する（UTC の 11/15 14:59 は、日本時間の 23:59）" do
      travel_to Time.utc(2026, 11, 15, 14, 59)
      expect(reservation.cancelable?).to be true

      travel_to Time.utc(2026, 11, 15, 15, 0)
      expect(reservation.cancelable?).to be false
    end

    it "締切の日数は、ルールの設定に従う（2日前なら、11/14 の23:59まで）" do
      MakeupRule.current.update!(reservation_deadline_days: 2)

      travel_to Time.zone.local(2026, 11, 14, 23, 59)
      expect(reservation.cancelable?).to be true

      travel_to Time.zone.local(2026, 11, 15, 0, 0)
      expect(reservation.cancelable?).to be false
    end

    it "締切を当日（0日前）にしても、枠が始まった後はキャンセルできない" do
      MakeupRule.current.update!(reservation_deadline_days: 0)

      travel_to Time.zone.local(2026, 11, 16, 9, 59)
      expect(reservation.cancelable?).to be true

      travel_to Time.zone.local(2026, 11, 16, 10, 0)
      expect(reservation.cancelable?).to be false
    end
  end

  it "すでにキャンセルした予約は、もう一度キャンセルできない（キャンセルした日時は変わらない）" do
    described_class.call(reservation)
    first_canceled_at = reservation.reload.canceled_at
    travel_to now + 1.hour

    result = described_class.call(reservation)

    expect(result.reason).to eq :already_canceled
    expect(reservation.reload.canceled_at).to eq first_canceled_at
  end

  describe "同時にキャンセルしたとき" do
    # 実際に複数のスレッドからキャンセルする。トランザクションをまたぐので、テストごとのロールバックは使わず、終わったら消す
    context "複数のスレッドから送る" do
      self.use_transactional_tests = false

      after do
        [ MakeupReservation, MakeupCredit, Absence, LessonSlot, Student, MakeupSlot, MakeupRule ].each(&:delete_all)
        User.delete_all
      end

      it "2回同時に送っても、キャンセルは1回だけ成功する" do
        reservation_id = reservation.id

        results = Array.new(2) do
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection { described_class.call(MakeupReservation.find(reservation_id)) }
          end
        end.map(&:value)

        expect(results.count(&:success?)).to eq 1
        expect(results.reject(&:success?).map(&:reason)).to eq [ :already_canceled ]
      end
    end
  end
end
