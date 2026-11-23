require "rails_helper"

RSpec.describe SetupProgress do
  def keys(steps)
    steps.map(&:key)
  end

  it "何も登録していないときは、4つの手順がすべて残っている（画面遷移図③の順）" do
    progress = described_class.new

    expect(progress).not_to be_complete
    expect(keys(progress.steps)).to eq %i[student lesson_slot makeup_slot makeup_rule]
    expect(progress.steps.map(&:label)).to eq [ "① 生徒を登録する", "② 固定枠を設定する", "② 振替枠を登録する", "③ 振替ルールを確認する" ]
    expect(keys(progress.remaining)).to eq %i[student lesson_slot makeup_slot makeup_rule]
  end

  it "生徒がいれば、「生徒を登録する」は完了" do
    create(:student)

    expect(keys(described_class.new.remaining)).to eq %i[lesson_slot makeup_slot makeup_rule]
  end

  it "固定枠があれば、「固定枠を設定する」は完了（生徒も登録ずみ）" do
    create(:lesson_slot)

    expect(keys(described_class.new.remaining)).to eq %i[makeup_slot makeup_rule]
  end

  it "振替枠があれば、「振替枠を登録する」は完了" do
    create(:makeup_slot)

    expect(keys(described_class.new.remaining)).to eq %i[student lesson_slot makeup_rule]
  end

  it "振替ルールは、行がない間は未完了。保存して行ができると完了" do
    expect(described_class.new.steps.last).not_to be_done

    MakeupRule.current.save!

    expect(described_class.new.steps.last).to be_done
  end

  it "すべて終わると、残りがなくなり、完了になる" do
    create(:lesson_slot)
    create(:makeup_slot)
    MakeupRule.current.save!

    progress = described_class.new

    expect(progress).to be_complete
    expect(progress.remaining).to be_empty
    expect(progress.steps).to all(be_done)
  end
end
