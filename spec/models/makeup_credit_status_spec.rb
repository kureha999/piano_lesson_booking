require "rails_helper"

# 振替権の状態の判定（README 12-6「振替権の状態の判定」）。状態は保存せず、予約と期限から判定する
RSpec.describe MakeupCredit do
  let(:now) { Time.zone.local(2026, 6, 10, 12, 0) }
  let(:credit_counter) { [ 0 ] } # 振替権を作った数（例ごとに 0 から）

  before { travel_to now }

  # 振替権を作る。固定枠は先生が1人なので重ならないように、1つ作るごとに欠席の曜日をずらす（6/15 月曜日から）
  def credit(expires_on: Date.new(2026, 6, 30))
    credit_counter[0] += 1
    create_credit_for(create(:student), Date.new(2026, 6, 14) + credit_counter[0]).tap { |c| c.update!(expires_on: expires_on) }
  end

  # 振替枠は重ならないように、枠ごとに別の時刻になる（factory の連番）。開始を指定するときは、重ならない時刻にする
  def reserve(makeup_credit, starts_at:, canceled: false)
    slot = create(:makeup_slot, starts_at: starts_at, ends_at: starts_at + 30.minutes)
    create(:makeup_reservation, makeup_credit: makeup_credit, makeup_slot: slot, canceled_at: (now if canceled))
  end

  def statuses(credit)
    {
      unused: described_class.unused.include?(credit),
      reserved: described_class.reserved.include?(credit),
      used: described_class.used.include?(credit),
      expired: described_class.expired.include?(credit)
    }
  end

  describe "未使用" do
    it "有効な予約がなく、今日が期限以内" do
      target = credit

      expect(target.status).to eq :unused
      expect(statuses(target)).to eq(unused: true, reserved: false, used: false, expired: false)
    end

    it "期限の当日は、まだ未使用（期限の日を含む）" do
      target = credit(expires_on: Date.new(2026, 6, 10))

      expect(target.status).to eq :unused
      expect(described_class.unused).to include(target)
    end

    it "予約をキャンセルすると、未使用に戻る" do
      target = credit
      reserve(target, starts_at: Time.zone.local(2026, 6, 20, 10, 0), canceled: true)

      expect(target.reload.status).to eq :unused
      expect(described_class.unused).to include(target)
    end
  end

  describe "期限切れ" do
    it "有効な予約がなく、期限の翌日になると期限切れ" do
      target = credit(expires_on: Date.new(2026, 6, 9))

      expect(target.status).to eq :expired
      expect(statuses(target)).to eq(unused: false, reserved: false, used: false, expired: true)
    end

    it "日本時間の日付で判定する（UTC では 6/9 でも、日本時間 6/10 の 0:30 は期限の翌日）" do
      target = credit(expires_on: Date.new(2026, 6, 9))
      travel_to Time.utc(2026, 6, 9, 15, 30) # 日本時間 6/10 0:30

      expect(target.status).to eq :expired
      expect(described_class.expired).to include(target)
    end

    it "日付が変わる瞬間（23:59:59 → 0:00）で、未使用から期限切れになる" do
      target = credit(expires_on: Date.new(2026, 6, 10))

      travel_to Time.zone.local(2026, 6, 10, 23, 59, 59)
      expect(target.status).to eq :unused

      travel_to Time.zone.local(2026, 6, 11, 0, 0, 0)
      expect(target.status).to eq :expired
      expect(described_class.expired).to include(target)
      expect(described_class.unused).not_to include(target)
    end
  end

  describe "予約済み" do
    it "有効な予約があり、振替枠の開始日時がまだ来ていない" do
      target = credit
      reserve(target, starts_at: Time.zone.local(2026, 6, 20, 10, 0))

      expect(target.reload.status).to eq :reserved
      expect(statuses(target)).to eq(unused: false, reserved: true, used: false, expired: false)
    end

    it "振替枠の開始の1分前までは、予約済み" do
      target = credit
      reserve(target, starts_at: now + 1.minute)

      expect(target.reload.status).to eq :reserved
    end

    it "期限を過ぎても、有効な予約があれば、期限切れにならない（期限は予約するときの条件）" do
      target = credit(expires_on: Date.new(2026, 6, 15))
      reserve(target, starts_at: Time.zone.local(2026, 6, 20, 10, 0)) # 受講日が期限後の予約は、通常は作れないが、状態は予約から判定する

      expect(target.reload.status).to eq :reserved
      expect(described_class.expired).not_to include(target)
    end
  end

  describe "使用済み" do
    it "有効な予約があり、振替枠の開始日時を過ぎた" do
      target = credit
      reserve(target, starts_at: Time.zone.local(2026, 6, 9, 10, 0))

      expect(target.reload.status).to eq :used
      expect(statuses(target)).to eq(unused: false, reserved: false, used: true, expired: false)
    end

    it "振替枠の開始ちょうどで、予約済みから使用済みになる" do
      target = credit
      reserve(target, starts_at: Time.zone.local(2026, 6, 10, 12, 0))

      expect(target.reload.status).to eq :used
      expect(described_class.reserved).not_to include(target)
    end

    it "振替枠の開始を過ぎれば、期限を過ぎていても使用済み（期限切れではない）" do
      target = credit(expires_on: Date.new(2026, 6, 5))
      reserve(target, starts_at: Time.zone.local(2026, 6, 5, 10, 0))

      expect(target.reload.status).to eq :used
      expect(described_class.expired).not_to include(target)
    end

    it "時間が進むと、予約済みから使用済みに変わる（状態は保存しない）" do
      target = credit
      reserve(target, starts_at: Time.zone.local(2026, 6, 20, 10, 0))
      expect(target.reload.status).to eq :reserved

      travel_to Time.zone.local(2026, 6, 20, 10, 1)

      expect(target.reload.status).to eq :used
      expect(described_class.used).to include(target)
    end
  end

  describe "スコープ" do
    it "4つの状態のどれか1つだけに当てはまる" do
      unused = credit
      expired = credit(expires_on: Date.new(2026, 6, 1))
      reserved = credit
      reserve(reserved, starts_at: Time.zone.local(2026, 6, 20, 10, 0))
      used = credit
      reserve(used, starts_at: Time.zone.local(2026, 6, 9, 10, 0))

      expect(described_class.unused).to contain_exactly(unused)
      expect(described_class.expired).to contain_exactly(expired)
      expect(described_class.reserved).to contain_exactly(reserved)
      expect(described_class.used).to contain_exactly(used)
    end

    it "いまの日時を引数で指定できる" do
      target = credit(expires_on: Date.new(2026, 6, 30))

      expect(described_class.unused(Time.zone.local(2026, 6, 30, 23, 59))).to include(target)
      expect(described_class.expired(Time.zone.local(2026, 7, 1, 0, 0))).to include(target)
      expect(target.status(Time.zone.local(2026, 7, 1, 0, 0))).to eq :expired
    end

    it "ほかのスコープと組み合わせられる（生徒の未使用の振替権）" do
      target = credit
      credit # ほかの生徒の振替権

      expect(described_class.where(student: target.student).unused).to contain_exactly(target)
    end
  end
end
