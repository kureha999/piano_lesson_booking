require "rails_helper"

RSpec.describe Absence do
  describe "factory" do
    it "有効な欠席を作る" do
      expect(build(:absence)).to be_valid
    end
  end

  describe "関連" do
    it "固定枠・連絡した人は必須" do
      absence = described_class.new

      expect(absence).not_to be_valid
      expect(absence.errors.attribute_names).to include(:lesson_slot, :reported_by, :lesson_on)
    end

    it "振替権がある欠席は、削除できない" do
      credit = create(:makeup_credit)

      expect(credit.absence.destroy).to be false
      expect(credit.absence.errors).not_to be_empty
    end

    it "欠席がある固定枠・連絡した人は、削除できない" do
      absence = create(:absence)

      expect(absence.lesson_slot.destroy).to be false
      expect(absence.reported_by.destroy).to be false
    end
  end

  describe "同じレッスンの欠席" do
    it "同じ固定枠・同じ日の欠席を2回登録できない" do
      first = create(:absence)
      duplicate = build(:absence, lesson_slot: first.lesson_slot, lesson_on: first.lesson_on)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:lesson_on]).to include "のレッスンは、すでに欠席を連絡しています"
    end

    it "検証を通り抜けても、DB の一意インデックスが2回目を止める" do
      first = create(:absence)
      duplicate = build(:absence, lesson_slot: first.lesson_slot, lesson_on: first.lesson_on)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "同じ固定枠でも、別の日なら登録できる" do
      first = create(:absence)

      expect(build(:absence, lesson_slot: first.lesson_slot, lesson_on: first.lesson_on + 7)).to be_valid
    end

    it "同じ日でも、別の固定枠なら登録できる" do
      first = create(:absence)
      other_slot = create(:lesson_slot, wday: 3, start_time: "17:00", end_time: "17:30")

      expect(build(:absence, lesson_slot: other_slot, lesson_on: first.lesson_on)).to be_valid
    end
  end

  describe "欠席する日" do
    it "固定枠の曜日でなければ登録できない" do
      absence = build(:absence, lesson_on: Date.new(2099, 1, 8)) # 木曜日

      expect(absence).not_to be_valid
      expect(absence.errors[:lesson_on]).to include "は固定枠の曜日（水曜日）ではありません"
    end

    it "適用開始日より前は登録できない" do
      slot = create(:lesson_slot, starts_on: Date.new(2099, 1, 14))

      expect(build(:absence, lesson_slot: slot, lesson_on: Date.new(2099, 1, 7))).not_to be_valid
      expect(build(:absence, lesson_slot: slot, lesson_on: Date.new(2099, 1, 14))).to be_valid
    end

    it "適用終了日より後は登録できない（終了日当日は登録できる）" do
      slot = create(:lesson_slot, ends_on: Date.new(2099, 1, 14))

      expect(build(:absence, lesson_slot: slot, lesson_on: Date.new(2099, 1, 14))).to be_valid
      absence = build(:absence, lesson_slot: slot, lesson_on: Date.new(2099, 1, 21))
      expect(absence).not_to be_valid
      expect(absence.errors[:lesson_on]).to include "は固定枠の適用期間外です"
    end

    it "適用終了日がない固定枠は、先の日でも登録できる" do
      expect(build(:absence, lesson_on: Date.new(2099, 12, 30))).to be_valid
    end
  end

  describe "レッスン開始前であること" do
    let(:slot) { create(:lesson_slot, start_time: "16:00", end_time: "16:30") } # 水曜日
    let(:lesson_day) { Date.new(2026, 6, 10) } # 水曜日

    it "開始の前なら登録できる" do
      travel_to Time.zone.local(2026, 6, 10, 15, 59) do
        expect(build(:absence, lesson_slot: slot, lesson_on: lesson_day)).to be_valid
      end
    end

    it "開始の時刻ちょうどは登録できない" do
      travel_to Time.zone.local(2026, 6, 10, 16, 0) do
        absence = build(:absence, lesson_slot: slot, lesson_on: lesson_day)

        expect(absence).not_to be_valid
        expect(absence.errors[:lesson_on]).to include "のレッスンはすでに始まっています"
      end
    end

    it "前の日のレッスンは登録できない" do
      travel_to Time.zone.local(2026, 6, 11, 9, 0) do
        expect(build(:absence, lesson_slot: slot, lesson_on: lesson_day)).not_to be_valid
      end
    end

    it "日本時間で判定する（UTC では前日でも、日本時間の当日 15:30 は登録できる）" do
      travel_to Time.utc(2026, 6, 10, 6, 30) do # 日本時間 15:30
        expect(build(:absence, lesson_slot: slot, lesson_on: lesson_day)).to be_valid
      end
    end

    it "登録済みの欠席は、レッスンが始まった後に更新しても無効にならない" do
      absence = create(:absence, lesson_slot: slot, lesson_on: Date.new(2099, 1, 7))

      travel_to Time.zone.local(2099, 1, 7, 17, 0) do
        absence.no_credit_reason = :over_monthly_limit

        expect(absence).to be_valid
      end
    end
  end

  describe "#lesson_starts_at" do
    it "欠席する日の、固定枠の開始時刻（日本時間）を返す" do
      absence = build(:absence, lesson_on: Date.new(2099, 1, 7))

      expect(absence.lesson_starts_at).to eq Time.zone.local(2099, 1, 7, 16, 0)
    end

    it "固定枠か日付がないときは nil" do
      expect(described_class.new.lesson_starts_at).to be_nil
    end
  end

  describe "振替権が付かない理由" do
    it "初期値は NULL（振替権あり）" do
      expect(build(:absence).no_credit_reason).to be_nil
    end

    it "締切後（0）と月の上限（1）を区別する" do
      slot = create(:lesson_slot)

      expect(create(:absence, :after_deadline, lesson_slot: slot).read_attribute_before_type_cast(:no_credit_reason)).to eq 0
      over = create(:absence, :over_monthly_limit, lesson_slot: slot, lesson_on: Date.new(2099, 1, 14))
      expect(over.read_attribute_before_type_cast(:no_credit_reason)).to eq 1
    end
  end
end
