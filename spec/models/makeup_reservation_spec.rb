require "rails_helper"

RSpec.describe MakeupReservation do
  describe "factory" do
    it "有効な振替予約を作る" do
      expect(build(:makeup_reservation)).to be_valid
    end
  end

  describe "関連" do
    it "振替権・振替枠・生徒は必須" do
      reservation = described_class.new

      expect(reservation).not_to be_valid
      expect(reservation.errors.attribute_names).to include(:makeup_credit, :makeup_slot, :student)
    end

    it "振替権を持つ生徒と違う生徒では、予約できない" do
      reservation = build(:makeup_reservation, student: create(:student))

      expect(reservation).not_to be_valid
      expect(reservation.errors[:student]).to include "は振替権を持つ生徒と同じである必要があります"
    end

    it "予約がある（キャンセルした予約も含む）振替権・生徒は、削除できない" do
      reservation = create(:makeup_reservation, :canceled)

      expect(reservation.makeup_credit.destroy).to be false
      expect(reservation.student.destroy).to be false
    end
  end

  describe "1つの振替権で、有効な予約は1つまで" do
    let!(:reservation) { create(:makeup_reservation) }

    it "有効な予約がある振替権で、2つ目の予約は作れない" do
      second = build(:makeup_reservation, makeup_credit: reservation.makeup_credit, makeup_slot: create(:makeup_slot))

      expect(second).not_to be_valid
      expect(second.errors[:makeup_credit_id]).to include "にはすでに有効な予約があります"
    end

    it "検証を通り抜けても、DB の部分一意インデックスが2つ目を止める" do
      second = build(:makeup_reservation, makeup_credit: reservation.makeup_credit, makeup_slot: create(:makeup_slot))

      expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "キャンセルすると、同じ振替権でもう一度予約できる（キャンセルした行は残る）" do
      reservation.update!(canceled_at: Time.current)
      second = build(:makeup_reservation, makeup_credit: reservation.makeup_credit, makeup_slot: create(:makeup_slot))

      expect(second).to be_valid
      expect { second.save! }.to change(described_class, :count).by(1)
      expect(described_class.where(makeup_credit: reservation.makeup_credit).count).to eq 2
    end

    it "キャンセルした予約は、いくつあっても構わない" do
      create(:makeup_reservation, :canceled, makeup_credit: reservation.makeup_credit)
      create(:makeup_reservation, :canceled, makeup_credit: reservation.makeup_credit)

      expect(described_class.where(makeup_credit: reservation.makeup_credit).count).to eq 3
    end
  end

  describe "同じ生徒が同じ枠を二重に予約しない" do
    let!(:reservation) { create(:makeup_reservation) }
    let(:student) { reservation.student }

    # 同じ生徒の、別の欠席の振替権
    def another_credit
      slot = reservation.makeup_credit.absence.lesson_slot
      absence = create(:absence, lesson_slot: slot, lesson_on: reservation.makeup_credit.absence.lesson_on + 7)
      create(:makeup_credit, absence: absence)
    end

    it "有効な予約がある枠を、別の振替権で予約し直せない" do
      second = build(:makeup_reservation, makeup_credit: another_credit, makeup_slot: reservation.makeup_slot)

      expect(second).not_to be_valid
      expect(second.errors[:student_id]).to include "はすでにこの枠を予約しています"
    end

    it "検証を通り抜けても、DB の部分一意インデックスが止める" do
      second = build(:makeup_reservation, makeup_credit: another_credit, makeup_slot: reservation.makeup_slot)

      expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "キャンセルした後なら、同じ枠を予約し直せる" do
      reservation.update!(canceled_at: Time.current)

      expect(build(:makeup_reservation, makeup_credit: another_credit, makeup_slot: reservation.makeup_slot)).to be_valid
    end

    it "ほかの生徒は、同じ枠を予約できる（定員の確認は別の issue）" do
      expect(build(:makeup_reservation, makeup_slot: reservation.makeup_slot)).to be_valid
    end
  end

  describe "有効・キャンセル" do
    # 固定枠は先生が1人なので重ならない。木曜日の枠の欠席に付いた振替権
    let(:credit_on_thursday) do
      slot = create(:lesson_slot, wday: 4)
      create(:makeup_credit, absence: create(:absence, lesson_slot: slot, lesson_on: Date.new(2099, 1, 8)))
    end

    it "canceled_at が NULL なら有効、日時があればキャンセル" do
      active = create(:makeup_reservation)
      canceled = create(:makeup_reservation, :canceled, makeup_credit: credit_on_thursday)

      expect(active).to be_active
      expect(canceled).to be_canceled
      expect(described_class.active).to contain_exactly(active)
    end
  end
end
