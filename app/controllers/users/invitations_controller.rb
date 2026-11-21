module Users
  # C-02 パスワード設定（招待メールのリンクから開く）。
  # 招待は、先生が生徒を登録したときに StudentForm が送る。devise_invitable が用意する
  # 「招待を送る画面」と「招待を取り消す（ユーザーを削除する）リンク」は使わないので、404 にする。
  class InvitationsController < Devise::InvitationsController
    prepend_before_action :reject_unused_actions, only: %i[new create destroy]

    protected

    # リンクが正しくない・使用済みのときの移動先。メッセージを消さないように、ログイン画面（C-01）へ直接移動する
    # （ルートを経由すると、そこでの移動でメッセージが消える）
    def after_sign_out_path_for(_resource_name)
      new_user_session_path
    end

    private

    def reject_unused_actions
      head :not_found
    end
  end
end
