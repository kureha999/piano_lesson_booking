module Teacher
  # T-08 振替ルールの設定（先生）。行がなければ初期値を表示し、保存すると行を1つ作る。2回目以降は同じ行を更新する
  class MakeupRulesController < ApplicationController
    def edit
      @makeup_rule = MakeupRule.current
      authorize @makeup_rule
    end

    def update
      @makeup_rule = MakeupRule.current
      authorize @makeup_rule
      @makeup_rule.assign_attributes(rule_params)

      if SaveMakeupRule.call(@makeup_rule)
        redirect_to teacher_root_path, notice: "振替ルールを保存しました。"
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def rule_params
      params.expect(makeup_rule: %i[monthly_limit valid_days absence_deadline_hours reservation_deadline_days])
    end
  end
end
