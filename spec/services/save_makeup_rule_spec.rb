require "rails_helper"

RSpec.describe SaveMakeupRule do
  it "保存できたら true を返す（行がなければ作り、2回目からは同じ行を更新する）" do
    rule = MakeupRule.current
    rule.monthly_limit = 5

    expect { expect(described_class.call(rule)).to be true }.to change(MakeupRule, :count).by(1)
    expect(MakeupRule.current.monthly_limit).to eq 5
  end

  it "検証に失敗したら false を返す" do
    rule = MakeupRule.current
    rule.monthly_limit = -1

    expect(described_class.call(rule)).to be false
    expect(rule.errors[:monthly_limit]).to be_present
  end

  it "行がない状態で同時に保存されて、主キーが重複したときは、エラーにして false を返す" do
    rule = MakeupRule.current
    allow(rule).to receive(:save).and_raise(ActiveRecord::RecordNotUnique)

    expect(described_class.call(rule)).to be false
    expect(rule.errors[:base].join).to include "同時に保存されました"
  end
end
