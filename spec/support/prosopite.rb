# N+1 クエリを検出したら、テストを失敗させる（Prosopite.raise = true は config/initializers/prosopite.rb）。
# example ごとに調べる。テストの準備（FactoryBot）は、N+1 になるのが普通なので除く。
# 別のスレッドで動くブラウザ側のサーバー（system spec）は、この scan の対象外。
# どうしても N+1 が避けられない example は、`prosopite: false` を付けて外せる（付けたら、理由をコメントに書く）。
RSpec.configure do |config|
  config.before { |example| Prosopite.scan(example.location) unless example.metadata[:prosopite] == false }
  config.after { Prosopite.finish }
end

Prosopite.pause_during("factory_bot.run_factory")

# 1つの example で、複数の画面を続けて開くときは、画面ごとに別の scan にする。
# 続けて開くと、リクエストごとに読むログイン中のユーザーなどが、「同じクエリの繰り返し」と数えられてしまうため。
module ProsopiteHelpers
  # ここまでの scan を終えて（N+1 があれば、ここで失敗する）、context の scan を新しく始める
  def new_scan(context)
    Prosopite.finish
    Prosopite.scan(context)
  end
end

RSpec.configure { |config| config.include ProsopiteHelpers, type: :request }
