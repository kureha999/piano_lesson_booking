# N+1 クエリの検出（Prosopite）。同じ呼び出し元から、値だけが違う同じ SQL が繰り返し実行されると、N+1 として報告する。
#   開発：リクエストごとに調べ、Rails のログと、画面左下のフッターに表示する（画面が redirect するときは、ログだけ）
#   テスト：N+1 を検出したら、テストを失敗させる（spec/rails_helper.rb で、example ごとに調べる）
#   本番：何もしない（gem は development・test のグループにだけ入れている）
if Rails.env.development?
  require "prosopite/middleware/rack"
  Rails.configuration.middleware.use(Prosopite::Middleware::Rack)

  Rails.application.config.after_initialize do
    Prosopite.add_footer = true # N+1 は、Rails のログにも出る（既定）
  end
end

if Rails.env.test?
  Rails.application.config.after_initialize do
    Prosopite.raise = true
  end
end
