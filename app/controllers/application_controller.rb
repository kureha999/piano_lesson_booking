class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # ログインしていなければ C-01 に移動する（Devise のコントローラーは対象外）。
  # 移動前の URL は Devise が覚えていて、ログイン後に戻る。
  before_action :authenticate_user!

  private

  # ログイン後の移動先。元の画面があればそこへ、なければロールごとのホームへ（先生は T-01、保護者は P-01）
  def after_sign_in_path_for(resource)
    stored_location_for(resource) || home_path_for(resource)
  end

  def home_path_for(user)
    user.teacher? ? teacher_root_path : root_path
  end
end
