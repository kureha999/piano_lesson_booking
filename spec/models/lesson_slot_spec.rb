require "rails_helper"

RSpec.describe LessonSlot do
  describe "factory" do
    it "有効な固定枠を作る" do
      expect(build(:lesson_slot)).to be_valid
    end
  end

  describe "関連" do
    it "生徒に属する" do
      expect(build(:lesson_slot, student: nil)).not_to be_valid
    end

    it "固定枠がある生徒は、削除できない" do
      slot = create(:lesson_slot)

      expect(slot.student.destroy).to be false
      expect(slot.student.errors).not_to be_empty
    end
  end

  describe "入力の検証" do
    it "曜日・開始時刻・終了時刻・適用開始日は必須" do
      slot = described_class.new

      expect(slot).not_to be_valid
      expect(slot.errors.attribute_names).to include(:student, :wday, :start_time, :end_time, :starts_on)
    end

    it "適用終了日は空でもよい（終わりなし）" do
      expect(build(:lesson_slot, ends_on: nil)).to be_valid
    end

    # N+1 の検出は外す：曜日を変えて、同じ検証を繰り返す
    it "曜日は 0〜6 だけ", prosopite: false do
      expect(build(:lesson_slot, wday: -1)).not_to be_valid
      expect(build(:lesson_slot, wday: 7)).not_to be_valid
      expect((0..6).map { |wday| build(:lesson_slot, wday: wday).valid? }).to all(be true)
    end

    it "終了時刻は開始時刻より後" do
      expect(build(:lesson_slot, start_time: "16:00", end_time: "16:00")).not_to be_valid
      slot = build(:lesson_slot, start_time: "16:00", end_time: "15:30")

      expect(slot).not_to be_valid
      expect(slot.errors[:end_time]).to include "は開始時刻より後にしてください"
    end

    it "適用終了日は適用開始日以降（同じ日はよい）" do
      expect(build(:lesson_slot, starts_on: Date.new(2026, 4, 1), ends_on: Date.new(2026, 4, 1))).to be_valid
      slot = build(:lesson_slot, starts_on: Date.new(2026, 4, 1), ends_on: Date.new(2026, 3, 31))

      expect(slot).not_to be_valid
      expect(slot.errors[:ends_on]).to include "は適用開始日以降にしてください"
    end

    it "時刻は日本時間の時刻のまま保存される（タイムゾーンで変換されない）" do
      slot = create(:lesson_slot, start_time: "16:00", end_time: "16:30")

      expect(slot.reload.start_time.strftime("%H:%M")).to eq "16:00"
      expect(slot.end_time.strftime("%H:%M")).to eq "16:30"
    end
  end

  describe "DB の CHECK 制約（バリデーションを通らなくても、ありえない値は入らない）" do
    def insert!(**changes)
      slot = build(:lesson_slot, **changes)
      slot.student.save!
      slot.save!(validate: false)
    end

    it "曜日が 0〜6 でない" do
      expect { insert!(wday: 7) }.to raise_error(ActiveRecord::StatementInvalid, /lesson_slots_wday_range/)
    end

    it "終了時刻が開始時刻以前" do
      expect { insert!(start_time: "16:00", end_time: "16:00") }
        .to raise_error(ActiveRecord::StatementInvalid, /lesson_slots_end_after_start/)
    end

    it "適用終了日が適用開始日より前" do
      expect { insert!(starts_on: Date.new(2026, 4, 1), ends_on: Date.new(2026, 3, 1)) }
        .to raise_error(ActiveRecord::StatementInvalid, /lesson_slots_ends_on_after_starts_on/)
    end
  end

  describe ".effective_on" do
    it "指定した日が、適用開始日から適用終了日までの間（両端を含む）の枠だけを返す" do
      open_ended = create(:lesson_slot, wday: 1, starts_on: Date.new(2026, 4, 1), ends_on: nil)
      limited = create(:lesson_slot, wday: 2, starts_on: Date.new(2026, 4, 1), ends_on: Date.new(2026, 6, 30))
      future = create(:lesson_slot, wday: 3, starts_on: Date.new(2026, 7, 1))

      expect(described_class.effective_on(Date.new(2026, 3, 31))).to be_empty
      expect(described_class.effective_on(Date.new(2026, 4, 1))).to contain_exactly(open_ended, limited)
      expect(described_class.effective_on(Date.new(2026, 6, 30))).to contain_exactly(open_ended, limited)
      expect(described_class.effective_on(Date.new(2026, 7, 1))).to contain_exactly(open_ended, future)
    end
  end

  describe ".in_weekly_order と表示用のメソッド" do
    it "曜日・開始時刻の順に並べる" do
      sat = create(:lesson_slot, wday: 6, start_time: "09:00", end_time: "09:30")
      wed_late = create(:lesson_slot, wday: 3, start_time: "17:00", end_time: "17:30")
      wed_early = create(:lesson_slot, wday: 3, start_time: "16:00", end_time: "16:30")

      expect(described_class.in_weekly_order).to eq [ wed_early, wed_late, sat ]
    end

    it "曜日の名前と時間の範囲を、日本語で返す" do
      slot = build(:lesson_slot, wday: 0, start_time: "09:05", end_time: "10:00")

      expect(slot.wday_name).to eq "日曜日"
      expect(slot.time_range).to eq "09:05〜10:00"
    end
  end

  describe "固定枠どうしの重なり（先生は1人）" do
    let!(:existing) { create(:lesson_slot, wday: 3, start_time: "16:00", end_time: "16:30", starts_on: Date.new(2026, 4, 1), ends_on: nil) }

    def overlap_error(**changes)
      slot = build(:lesson_slot, **changes)
      slot.valid?
      slot.errors[:base]
    end

    it "別の生徒でも、同じ曜日・同じ時間・重なる期間なら登録できない" do
      expect(overlap_error).to include "同じ曜日・時間・期間に、ほかの固定枠があります"
    end

    it "時間が一部重なるときも、登録できない" do
      expect(overlap_error(start_time: "16:15", end_time: "16:45")).not_to be_empty
      expect(overlap_error(start_time: "15:45", end_time: "16:15")).not_to be_empty
      expect(overlap_error(start_time: "15:00", end_time: "17:00")).not_to be_empty
    end

    it "時間が接しているだけ（16:30 から始まる）なら登録できる" do
      expect(build(:lesson_slot, start_time: "16:30", end_time: "17:00")).to be_valid
      expect(build(:lesson_slot, start_time: "15:30", end_time: "16:00")).to be_valid
    end

    it "曜日が違えば登録できる" do
      expect(build(:lesson_slot, wday: 4)).to be_valid
    end

    it "期間が重ならなければ、同じ曜日・時間でも登録できる" do
      existing.update!(ends_on: Date.new(2026, 9, 30))

      expect(build(:lesson_slot, starts_on: Date.new(2026, 10, 1))).to be_valid
      expect(build(:lesson_slot, starts_on: Date.new(2026, 9, 30))).not_to be_valid
    end

    it "適用終了日のある新しい枠が、既存の枠の開始前に収まるなら登録できる" do
      expect(build(:lesson_slot, starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 3, 31))).to be_valid
      expect(build(:lesson_slot, starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 4, 1))).not_to be_valid
    end

    it "自分自身は重なりに数えない（更新できる）" do
      existing.end_time = "16:40"

      expect(existing).to be_valid
    end

    it "枠の変更は、今の枠に適用終了日を入れて新しい枠を作る形で登録できる" do
      existing.update!(ends_on: Date.new(2026, 9, 30))
      changed = build(:lesson_slot, student: existing.student, wday: 3, start_time: "17:00", end_time: "17:30", starts_on: Date.new(2026, 10, 1))

      expect(changed).to be_valid
    end
  end
end
