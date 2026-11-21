class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # ログインしていなければ C-01 に移動する（Devise のコントローラーは対象外）。
  # 移動前の URL は Devise が覚えていて、ログイン後に戻る。
  before_action :authenticate_user!

  # authorize・policy_scope の呼び忘れを検出する。
  # 呼び忘れた画面は、開発・テストでエラーになるので、権限のチェック漏れに気づける。
  after_action :verify_authorized, unless: :skip_authorization_check?
  after_action :verify_policy_scoped, if: :verify_policy_scoped?

  # 権限がない画面を開いたら、自分のホーム（先生は T-01、保護者は P-01）に戻してメッセージを表示する。
  # ほかの家庭のデータは、policy_scope で絞った中から find するので、RecordNotFound（E-01：404）になる。
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  # Devise のコントローラー（ログイン・パスワード再設定）は、ログインしていなくても開くので対象外
  def skip_authorization_check?
    devise_controller?
  end

  # 一覧（index）では、policy_scope で見てよいデータに絞っているかも確認する。
  # （only: :index と書くと、index がないコントローラーで Rails がエラーにするため、条件で判定する）
  def verify_policy_scoped?
    action_name == "index" && !skip_authorization_check?
  end

  def user_not_authorized
    redirect_to home_path_for(current_user), alert: "この画面を開く権限がありません。"
  end

  # ログイン後の移動先。元の画面があればそこへ、なければロールごとのホームへ（先生は T-01、保護者は P-01）
  def after_sign_in_path_for(resource)
    stored_location_for(resource) || home_path_for(resource)
  end

  def home_path_for(user)
    user.teacher? ? teacher_root_path : root_path
  end
end
