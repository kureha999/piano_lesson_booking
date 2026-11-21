require "rails_helper"

RSpec.describe MakeupSlot do
  def at(day, hour, min = 0)
    Time.zone.local(2026, 6, day, hour, min)
  end

  describe "factory" do
    it "有効な振替枠を作り、定員の初期値は1" do
      slot = build(:makeup_slot)

      expect(slot).to be_valid
      expect(described_class.new.capacity).to eq 1
    end

    it "続けて作っても、時間が重ならない" do
      expect { create_list(:makeup_slot, 3) }.not_to raise_error
    end
  end

  describe "入力の検証" do
    it "開始日時・終了日時は必須" do
      slot = described_class.new(capacity: 1)

      expect(slot).not_to be_valid
      expect(slot.errors.attribute_names).to include(:starts_at, :ends_at)
    end

    it "終了日時は開始日時より後" do
      expect(build(:makeup_slot, starts_at: at(1, 10), ends_at: at(1, 10))).not_to be_valid
      slot = build(:makeup_slot, starts_at: at(1, 10), ends_at: at(1, 9))

      expect(slot).not_to be_valid
      expect(slot.errors[:ends_at]).to include "は開始日時より後にしてください"
    end

    it "定員は1以上の整数" do
      expect(build(:makeup_slot, capacity: 1)).to be_valid
      expect(build(:makeup_slot, capacity: 3)).to be_valid
      expect(build(:makeup_slot, capacity: 0)).not_to be_valid
      expect(build(:makeup_slot, capacity: -1)).not_to be_valid
      expect(build(:makeup_slot, capacity: 1.5)).not_to be_valid
      expect(build(:makeup_slot, capacity: nil)).not_to be_valid
    end

    it "日時は日本時間で扱い、UTC で保存される" do
      slot = create(:makeup_slot, starts_at: at(1, 10), ends_at: at(1, 10, 30))

      expect(slot.reload.starts_at.zone).to eq "JST"
      expect(slot.starts_at.utc).to eq Time.utc(2026, 6, 1, 1, 0)
    end
  end

  describe "DB の制約（バリデーションを通らなくても、ありえない値は入らない）" do
    def insert!(**changes)
      build(:makeup_slot, **changes).save!(validate: false)
    end

    it "終了日時が開始日時以前" do
      expect { insert!(starts_at: at(1, 10), ends_at: at(1, 10)) }
        .to raise_error(ActiveRecord::StatementInvalid, /makeup_slots_ends_after_starts/)
    end

    it "定員が1未満" do
      expect { insert!(capacity: 0) }.to raise_error(ActiveRecord::StatementInvalid, /makeup_slots_capacity_positive/)
    end

    it "時間が重なる振替枠（排他制約）" do
      create(:makeup_slot, starts_at: at(1, 10), ends_at: at(1, 11))

      expect { insert!(starts_at: at(1, 10, 30), ends_at: at(1, 11, 30)) }
        .to raise_error(ActiveRecord::StatementInvalid, /makeup_slots_no_overlap/)
    end

    it "完全に含まれる・含む振替枠も、排他制約で止まる" do
      create(:makeup_slot, starts_at: at(1, 10), ends_at: at(1, 12))

      expect { insert!(starts_at: at(1, 10, 30), ends_at: at(1, 11)) }.to raise_error(ActiveRecord::StatementInvalid, /makeup_slots_no_overlap/)
      expect { insert!(starts_at: at(1, 9), ends_at: at(1, 13)) }.to raise_error(ActiveRecord::StatementInvalid, /makeup_slots_no_overlap/)
    end

    it "終了と開始が同じ（続けて並ぶ）振替枠は、重ならない" do
      create(:makeup_slot, starts_at: at(1, 10), ends_at: at(1, 11))

      expect { insert!(starts_at: at(1, 11), ends_at: at(1, 12)) }.not_to raise_error
    end
  end

  describe "振替枠どうしの重なり" do
    let!(:existing) { create(:makeup_slot, starts_at: at(1, 10), ends_at: at(1, 11)) }

    it "時間が一部でも重なるなら、登録できない" do
      slot = build(:makeup_slot, starts_at: at(1, 10, 30), ends_at: at(1, 11, 30))

      expect(slot).not_to be_valid
      expect(slot.errors[:base]).to include "同じ時間に、ほかの振替枠があります"
    end

    it "接しているだけなら、登録できる" do
      expect(build(:makeup_slot, starts_at: at(1, 11), ends_at: at(1, 12))).to be_valid
      expect(build(:makeup_slot, starts_at: at(1, 9), ends_at: at(1, 10))).to be_valid
    end

    it "別の日なら、登録できる" do
      expect(build(:makeup_slot, starts_at: at(2, 10), ends_at: at(2, 11))).to be_valid
    end

    it "自分自身は重なりに数えない（更新できる）" do
      existing.capacity = 2
      existing.ends_at = at(1, 11, 30)

      expect(existing).to be_valid
    end
  end

  describe "固定枠との重なり" do
    # 2026-06-10 は水曜日
    before { create(:lesson_slot, wday: 3, start_time: "16:00", end_time: "16:30", starts_on: Date.new(2026, 4, 1)) }

    it "固定枠のレッスンの時間と重なるなら、登録できない" do
      slot = build(:makeup_slot, starts_at: at(10, 16, 15), ends_at: at(10, 16, 45))

      expect(slot).not_to be_valid
      expect(slot.errors[:base]).to include "固定枠（毎週のレッスン）の時間と重なっています"
    end

    it "長い振替枠が、固定枠のレッスンをまたぐときも登録できない" do
      expect(build(:makeup_slot, starts_at: at(10, 15), ends_at: at(10, 18))).not_to be_valid
    end

    it "固定枠のレッスンの時間に接しているだけなら、登録できる" do
      expect(build(:makeup_slot, starts_at: at(10, 16, 30), ends_at: at(10, 17))).to be_valid
      expect(build(:makeup_slot, starts_at: at(10, 15, 30), ends_at: at(10, 16))).to be_valid
    end

    it "固定枠と同じ時間でも、曜日が違えば登録できる" do
      expect(build(:makeup_slot, starts_at: at(11, 16), ends_at: at(11, 16, 30))).to be_valid
    end

    it "固定枠の適用開始日より前・適用終了日より後の日は、重ならない" do
      LessonSlot.destroy_all
      create(:lesson_slot, wday: 3, start_time: "16:00", end_time: "16:30", starts_on: Date.new(2026, 6, 17), ends_on: Date.new(2026, 6, 24))

      expect(build(:makeup_slot, starts_at: at(10, 16), ends_at: at(10, 16, 30))).to be_valid # 開始日前
      expect(build(:makeup_slot, starts_at: at(17, 16), ends_at: at(17, 16, 30))).not_to be_valid # 開始日当日
      expect(build(:makeup_slot, starts_at: at(24, 16), ends_at: at(24, 16, 30))).not_to be_valid # 終了日当日
      expect(build(:makeup_slot, starts_at: Time.zone.local(2026, 7, 1, 16, 0), ends_at: Time.zone.local(2026, 7, 1, 16, 30))).to be_valid # 終了日後
    end

    it "日をまたぐ振替枠でも、翌日の固定枠と重なれば登録できない" do
      expect(build(:makeup_slot, starts_at: at(9, 23), ends_at: at(10, 16, 10))).not_to be_valid
    end
  end
end
