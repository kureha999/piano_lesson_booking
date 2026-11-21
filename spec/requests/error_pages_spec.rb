require "rails_helper"

RSpec.describe "エラーページ（E-01・E-02）", type: :request do
  # 本番では、例外が起きると ActionDispatch::PublicExceptions が public/<ステータス>.html を返す。
  # テスト環境は例外の詳細を画面に出す設定なので、その部分を直接呼んで確かめる。
  def render_error(status)
    env = Rack::MockRequest.env_for("/#{status}", "action_dispatch.exception" => nil)
    env["PATH_INFO"] = "/#{status}"
    code, _headers, body = ActionDispatch::PublicExceptions.new(Rails.public_path).call(env)
    [ code, body.each.to_a.join ]
  end

  {
    404 => [ "ページが見つかりません", "お探しのページは" ],
    500 => [ "エラーが発生しました", "サーバーでエラーが起きました" ]
  }.each do |status, (heading, message)|
    describe "#{status}" do
      let(:html) { File.read(Rails.public_path.join("#{status}.html")) }
      let(:page) { Nokogiri::HTML5.parse(html) }

      it "日本語のページを返す" do
        code, body = render_error(status)

        expect(code).to eq status
        expect(body).to include heading, message
      end

      it "日本語の lang・タイトル・見出しを持つ" do
        expect(page.at_css("html")["lang"]).to eq "ja"
        expect(page.at_css("title").text).to eq "#{heading} | ふりかえ帳"
        expect(page.at_css("h1").text).to eq heading
      end

      it "ホームに戻るリンクがある" do
        link = page.at_css("a.button")

        expect(link.text).to eq "ホームに戻る"
        expect(link["href"]).to eq "/"
      end

      it "外部のファイルを読み込まない（500 のときもアセットなしで表示できる）" do
        expect(page.css("script, link[rel=stylesheet]")).to be_empty
      end
    end
  end
end
