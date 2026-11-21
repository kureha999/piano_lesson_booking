require "rails_helper"

RSpec.describe LessonSlotForm do
  let(:student) { create(:student) }
  let(:attributes) do
    { student_id: student.id, wday: 3, start_time: "16:00", end_time: "16:30", starts_on: Date.new(2026, 4, 1) }
  end

  describe "登録" do
    it "固定枠を作る" do
      form = described_class.new(**attributes)

      expect { expect(form.save).to be true }.to change(LessonSlot, :count).by(1)
      expect(form.lesson_slot).to have_attributes(student: student, wday: 3, starts_on: Date.new(2026, 4, 1), ends_on: nil)
      expect(form.lesson_slot.time_range).to eq "16:00〜16:30"
    end

    it "入力エラーは、すべての項目について同時に返し、何も保存しない" do
      form = described_class.new(student_id: nil, wday: nil, start_time: "", end_time: "", starts_on: nil)

      expect { expect(form.save).to be false }.not_to change(LessonSlot, :count)
      expect(form.errors.attribute_names).to contain_exactly(:student_id, :wday, :start_time, :end_time, :starts_on)
      expect(form.errors.full_messages).to include "生徒を選んでください", "曜日を入力してください", "開始時刻を入力してください", "適用開始日を入力してください"
    end

    it "終了時刻が開始時刻より前なら、終了時刻のエラーにする" do
      form = described_class.new(**attributes, end_time: "15:30")

      expect(form.save).to be false
      expect(form.errors.full_messages).to include "終了時刻は開始時刻より後にしてください"
    end

    it "ほかの固定枠と時間が重なるときは、重なるというエラーを返す（別の生徒の枠とも）" do
      create(:lesson_slot, wday: 3, start_time: "16:00", end_time: "16:30", starts_on: Date.new(2026, 1, 1))
      form = described_class.new(**attributes, start_time: "16:15", end_time: "16:45")

      expect { expect(form.save).to be false }.not_to change(LessonSlot, :count)
      expect(form.errors[:base]).to include "同じ曜日・時間・期間に、ほかの固定枠があります"
    end
  end

  describe "変更（今の枠を終了し、新しい枠を作る）" do
    let!(:current) { create(:lesson_slot, student: student, wday: 3, start_time: "16:00", end_time: "16:30", starts_on: Date.new(2026, 4, 1)) }

    def change_form(**changes)
      described_class.for(current).tap do |form|
        changes.each { |name, value| form.public_send(:"#{name}=", value) }
      end
    end

    it "今の枠に適用終了日（新しい枠の開始日の前日）を入れ、新しい枠を作る" do
      form = change_form(wday: 4, start_time: "17:00", end_time: "17:30", starts_on: Date.new(2026, 10, 1))

      expect { expect(form.save).to be true }.to change(LessonSlot, :count).by(1)

      expect(current.reload.ends_on).to eq Date.new(2026, 9, 30)
      expect(form.lesson_slot).to have_attributes(student: student, wday: 4, starts_on: Date.new(2026, 10, 1), ends_on: nil)
      expect(form.lesson_slot.time_range).to eq "17:00〜17:30"
    end

    it "今の枠の曜日・時間は変わらない（過去の欠席が、元の曜日・時間のまま残る）" do
      form = change_form(wday: 5, start_time: "10:00", end_time: "10:30", starts_on: Date.new(2026, 10, 1))
      form.save

      expect(current.reload).to have_attributes(wday: 3, starts_on: Date.new(2026, 4, 1))
      expect(current.time_range).to eq "16:00〜16:30"
      expect(current.wday_name).to eq "水曜日"
    end

    it "古い枠は、過去の日には有効なまま、新しい枠の開始日からは有効でなくなる" do
      change_form(wday: 4, starts_on: Date.new(2026, 10, 1)).save

      expect(LessonSlot.effective_on(Date.new(2026, 9, 30))).to contain_exactly(current)
      expect(LessonSlot.effective_on(Date.new(2026, 10, 1)).pluck(:wday)).to eq [ 4 ]
    end

    it "すでに適用終了日が決まっている枠は、それより早い方を使う" do
      current.update!(ends_on: Date.new(2026, 8, 31))
      change_form(wday: 4, starts_on: Date.new(2026, 10, 1)).save

      expect(current.reload.ends_on).to eq Date.new(2026, 8, 31)
    end

    it "曜日・時間が変わらないときは、何も保存しない" do
      form = change_form(starts_on: Date.new(2026, 10, 1))

      expect { expect(form.save).to be true }.not_to change(LessonSlot, :count)
      expect(form).to be_unchanged
      expect(current.reload.ends_on).to be_nil
    end

    it "新しい枠の適用開始日が、今の枠の適用開始日以前なら、エラーにして何も変えない" do
      form = change_form(wday: 4, starts_on: Date.new(2026, 4, 1))

      expect { expect(form.save).to be false }.not_to change(LessonSlot, :count)
      expect(form.errors.full_messages).to include "適用開始日は、今の枠の適用開始日（2026年4月1日）より後にしてください"
      expect(current.reload.ends_on).to be_nil
    end

    it "適用開始日が空ならエラーにする" do
      form = change_form(wday: 4, starts_on: nil)

      expect(form.save).to be false
      expect(form.errors.full_messages).to include "適用開始日を入力してください"
    end

    it "新しい枠がほかの生徒の枠と重なるときは、エラーを返し、今の枠にも適用終了日を入れない（元に戻す）" do
      create(:lesson_slot, wday: 4, start_time: "17:00", end_time: "17:30", starts_on: Date.new(2026, 1, 1))
      form = change_form(wday: 4, start_time: "17:15", end_time: "17:45", starts_on: Date.new(2026, 10, 1))

      expect { expect(form.save).to be false }.not_to change(LessonSlot, :count)
      expect(form.errors[:base]).to include "同じ曜日・時間・期間に、ほかの固定枠があります"
      expect(current.reload.ends_on).to be_nil
      expect(form.lesson_slot.ends_on).to be_nil
    end

    it "終了時刻が開始時刻より前なら、エラーにして今の枠を変えない" do
      form = change_form(start_time: "17:00", end_time: "16:00", starts_on: Date.new(2026, 10, 1))

      expect(form.save).to be false
      expect(form.errors.full_messages).to include "終了時刻は開始時刻より後にしてください"
      expect(current.reload.ends_on).to be_nil
    end

    it "同じ曜日・時間帯のまま、時間だけ延ばす変更もできる（今の枠は前日で終わるので、重ならない）" do
      form = change_form(end_time: "17:00", starts_on: Date.new(2026, 10, 1))

      expect(form.save).to be true
      expect(form.lesson_slot.time_range).to eq "16:00〜17:00"
    end
  end

  describe ".for" do
    it "今の枠の値が入り、新しい枠の適用開始日は今日になる" do
      travel_to Time.zone.local(2026, 6, 10, 12, 0) do
        slot = create(:lesson_slot, start_time: "09:05", end_time: "10:00", starts_on: Date.new(2026, 4, 1))
        form = described_class.for(slot)

        expect(form).to have_attributes(student_id: slot.student_id, wday: 3, start_time: "09:05", end_time: "10:00", starts_on: Date.new(2026, 6, 10))
        expect(form).to be_persisted
      end
    end

    it "今日に始まった枠は、適用開始日を翌日にする（今の枠の開始日より後にするため）" do
      travel_to Time.zone.local(2026, 6, 10, 12, 0) do
        slot = create(:lesson_slot, starts_on: Date.new(2026, 6, 10))

        expect(described_class.for(slot).starts_on).to eq Date.new(2026, 6, 11)
      end
    end
  end
end
