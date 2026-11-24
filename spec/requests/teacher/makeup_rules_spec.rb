require "rails_helper"

RSpec.describe "振替ルールの設定（T-08）", type: :request do
  def field_value(name)
    Nokogiri::HTML5.parse(response.body).at_css("input[name='makeup_rule[#{name}]']")["value"]
  end

  let(:valid_params) do
    { makeup_rule: { monthly_limit: "3", valid_days: "45", absence_deadline_hours: "4", reservation_deadline_days: "2" } }
  end

  context "先生のとき" do
    before { sign_in create(:teacher) }

    it "行がない間は、初期値が入った状態で表示する" do
      get edit_teacher_makeup_rule_path

      expect(response).to have_http_status :ok
      expect(%w[monthly_limit valid_days absence_deadline_hours reservation_deadline_days].map { |name| field_value(name) }).to eq %w[2 30 2 1]
      expect(response.body).to include "月の上限回数", "振替の期限", "欠席連絡の締切", "振替予約の締切", "保存する"
    end

    it "メニューに「振替ルール」を表示する" do
      get edit_teacher_makeup_rule_path

      expect(Nokogiri::HTML5.parse(response.body).css("a.nav-link").map(&:text)).to include "振替ルール"
    end

    it "保存すると行が1つだけ作られ、T-01 に戻って「保存しました」を表示する（画面遷移図③）" do
      expect { patch teacher_makeup_rule_path, params: valid_params }.to change(MakeupRule, :count).by(1)

      expect(response).to redirect_to teacher_root_path
      follow_redirect!
      expect(response.body).to include "振替ルールを保存しました。"
      expect(MakeupRule.sole).to have_attributes(id: 1, monthly_limit: 3, valid_days: 45, absence_deadline_hours: 4, reservation_deadline_days: 2)

      get edit_teacher_makeup_rule_path # 保存した値は、T-08 を開き直すと表示される
      expect(field_value("monthly_limit")).to eq "3"
    end

    it "保存して戻った T-01 では、初期設定の③が完了になり、リンクが外れる" do
      patch teacher_makeup_rule_path, params: valid_params
      follow_redirect!

      setup_card = Nokogiri::HTML5.parse(response.body).at_css("section[aria-labelledby='setup-heading']")
      expect(setup_card.css("li").map { |li| li.text.squish }).to include "✓ ③ 振替ルールを確認する（完了）"
      expect(setup_card.css("li a").map(&:text)).not_to include "③ 振替ルールを確認する"
    end

    it "2回目以降は、同じ行を更新する" do
      patch teacher_makeup_rule_path, params: valid_params

      expect {
        patch teacher_makeup_rule_path, params: { makeup_rule: { monthly_limit: "5", valid_days: "10", absence_deadline_hours: "0", reservation_deadline_days: "0" } }
      }.not_to change(MakeupRule, :count)

      expect(MakeupRule.sole).to have_attributes(monthly_limit: 5, valid_days: 10, absence_deadline_hours: 0, reservation_deadline_days: 0)
    end

    it "入力エラーは、同じ画面の項目の下に表示し、保存しない" do
      expect {
        patch teacher_makeup_rule_path, params: { makeup_rule: { monthly_limit: "", valid_days: "-1", absence_deadline_hours: "1.5", reservation_deadline_days: "1" } }
      }.not_to change(MakeupRule, :count)

      expect(response).to have_http_status :unprocessable_content
      messages = Nokogiri::HTML5.parse(response.body).css(".invalid-feedback").map { |node| node.text.strip }
      expect(messages).to include "月の上限回数を入力してください", "振替の期限は0以上の値にしてください", "欠席連絡の締切は整数で入力してください"
      expect(field_value("valid_days")).to eq "-1"
    end

    it "行がない状態で同時に保存されたときは、エラーを表示する" do
      allow_any_instance_of(MakeupRule).to receive(:save).and_raise(ActiveRecord::RecordNotUnique) # rubocop:disable RSpec/AnyInstance

      patch teacher_makeup_rule_path, params: valid_params

      expect(response).to have_http_status :unprocessable_content
      expect(response.body).to include "ほかの画面で同時に保存されました。"
    end
  end

  context "保護者のとき" do
    before { sign_in create(:guardian) }

    it "表示も更新もできず、P-01 に戻す" do
      get edit_teacher_makeup_rule_path
      expect(response).to redirect_to root_path

      expect { patch teacher_makeup_rule_path, params: valid_params }.not_to change(MakeupRule, :count)
      expect(response).to redirect_to root_path
    end
  end

  context "ログインしていないとき" do
    it "C-01 に移動する" do
      get edit_teacher_makeup_rule_path

      expect(response).to redirect_to new_user_session_path
    end
  end
end
