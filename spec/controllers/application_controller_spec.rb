require "rails_helper"

# ApplicationController の共通の仕組み（権限のチェック漏れの検出、権限がないときの移動）を、
# 画面を持たない仮のコントローラーで確かめる。
RSpec.describe ApplicationController, type: :controller do
  controller do
    def index
      render plain: "ok"
    end

    def show
      render plain: "ok"
    end

    def edit
      authorize [ :teacher, :dashboard ], :show?
      render plain: "ok"
    end

    def new
      authorize :home, :show?
      render plain: "ok"
    end
  end

  describe "権限のチェック漏れの検出" do
    before { sign_in create(:guardian) }

    it "authorize を呼び忘れたアクションは、エラーになる" do
      expect { get :show, params: { id: 1 } }.to raise_error(Pundit::AuthorizationNotPerformedError)
    end

    it "一覧で policy_scope を呼び忘れたときも、エラーになる" do
      expect { get :index }.to raise_error(Pundit::PolicyScopingNotPerformedError)
    end

    it "authorize を呼んでいれば、エラーにならない" do
      get :new

      expect(response).to have_http_status :ok
    end
  end

  describe "権限がないとき" do
    it "保護者は P-01 に戻され、メッセージが表示される" do
      sign_in create(:guardian)

      get :edit, params: { id: 1 }

      expect(response).to redirect_to root_path
      expect(flash[:alert]).to eq "この画面を開く権限がありません。"
    end

    it "先生が権限のない画面を開いたときは、T-01 に戻される" do
      allow_any_instance_of(Teacher::DashboardPolicy).to receive(:show?).and_return(false) # rubocop:disable RSpec/AnyInstance
      sign_in create(:teacher)

      get :edit, params: { id: 1 }

      expect(response).to redirect_to teacher_root_path
    end

    it "権限があれば、そのまま表示する" do
      sign_in create(:teacher)

      get :edit, params: { id: 1 }

      expect(response).to have_http_status :ok
    end
  end

  describe "ログインしていないとき" do
    it "C-01 に移動する（権限のチェックより先に判定する）" do
      get :new

      expect(response).to redirect_to new_user_session_path
    end
  end
end
