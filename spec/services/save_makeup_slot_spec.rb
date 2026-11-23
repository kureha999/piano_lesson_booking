require "rails_helper"

RSpec.describe SaveMakeupSlot do
  let(:slot) { build(:makeup_slot) }

  it "保存できたら true を返し、保存する" do
    expect { expect(described_class.call(slot)).to be true }.to change(MakeupSlot, :count).by(1)
  end

  it "検証に失敗したら false を返し、何も保存しない" do
    slot.capacity = 0

    expect { expect(described_class.call(slot)).to be false }.not_to change(MakeupSlot, :count)
    expect(slot.errors[:capacity]).to be_present
  end

  it "検証のあと、保存の直前に同じ時間の枠が登録されたら（DB の排他制約）、重なりのエラーにする" do
    other = create(:makeup_slot, starts_at: slot.starts_at, ends_at: slot.ends_at)
    allow(slot).to receive(:valid?).and_return(true) # 検証をすり抜けた状態を再現する

    expect(described_class.call(slot)).to be false
    expect(slot.errors[:base].join).to include "ほかの振替枠が登録されました"
    expect(MakeupSlot.pluck(:id)).to eq [ other.id ]
  end

  it "排他制約以外の DB エラーは、そのまま投げる" do
    allow(slot).to receive(:save).and_raise(ActiveRecord::StatementInvalid, "other error")

    expect { described_class.call(slot) }.to raise_error(ActiveRecord::StatementInvalid)
  end
end
