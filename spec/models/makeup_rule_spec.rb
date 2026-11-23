require "rails_helper"

RSpec.describe MakeupRule do
  describe ".current" do
    it "行がないときは、初期値が入った未保存のルールを返す" do
      rule = described_class.current

      expect(rule).to be_new_record
      expect(rule).to have_attributes(monthly_limit: 2, valid_days: 30, absence_deadline_hours: 2, reservation_deadline_days: 1)
      expect(described_class.count).to eq 0
    end

    it "保存すると行が1つだけできて、2回目以降は同じ行を更新する" do
      described_class.current.update!(monthly_limit: 3)
      described_class.current.update!(monthly_limit: 4)

      expect(described_class.count).to eq 1
      expect(described_class.sole).to have_attributes(id: 1, monthly_limit: 4)
    end
  end

  describe "検証" do
    %i[monthly_limit valid_days absence_deadline_hours reservation_deadline_days].each do |attribute|
      it "#{attribute} は、空・小数・負の数を受け付けず、0は受け付ける" do
        rule = described_class.current

        [ nil, 1.5, -1 ].each do |value|
          rule[attribute] = value
          expect(rule).not_to be_valid
        end
        rule[attribute] = 0
        expect(rule).to be_valid
      end
    end
  end

  describe "DB の制約" do
    it "id = 1 以外の行は保存できない" do
      expect { described_class.new(id: 2).save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /makeup_rules_single_row/)
    end

    it "各項目が負の数の行は保存できない" do
      expect { described_class.new(id: 1, valid_days: -1).save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /valid_days_non_negative/)
    end
  end
end
