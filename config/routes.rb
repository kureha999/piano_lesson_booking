Rails.application.routes.draw do
  # ログイン・ログアウト（C-01）。先生と保護者で同じ画面を使う。
  # 新規登録の画面は作らない（保護者は招待、先生はコマンドで作成する）。パスワード再設定（C-03・C-04）は /password/new・/password/edit。
  # 招待メールのリンクから開くパスワード設定（C-02）は /invitation/accept
  devise_for :users, path: "", path_names: { sign_in: "login", sign_out: "logout" },
    only: %i[sessions passwords invitations], controllers: { invitations: "users/invitations" }

  # 先生の画面
  namespace :teacher do
    root "dashboard#show" # T-01 ダッシュボード
    resources :students, only: %i[index new create edit update] # T-02 生徒一覧、T-03 生徒の登録・編集
    resources :lesson_slots, only: :index # T-04 固定枠の一覧（T-05 の登録・編集は別の issue）
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # 開発環境で送ったメールの一覧（development のみ）
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  # P-01 ホーム（保護者）。先生が開いたら T-01 に移動する
  root "home#show"
end
