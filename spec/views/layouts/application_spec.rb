require "rails_helper"

RSpec.describe "layouts/application", type: :view do
  let(:page) { Nokogiri::HTML5.parse(rendered) }

  it "スマホ向けの viewport と日本語の lang を設定する" do
    render template: "layouts/application"

    expect(page.at_css("html")["lang"]).to eq "ja"
    expect(page.at_css("meta[name=viewport]")["content"]).to include "width=device-width"
  end

  it "ヘッダーとメッセージ、各画面の内容を表示する" do
    flash[:notice] = "保存しました"
    view.content_for(:menu, '<li class="nav-item"><a class="nav-link" href="/x">メニュー項目</a></li>'.html_safe)

    render inline: "<p>画面の中身</p>", layout: "layouts/application"

    expect(page.at_css("header .navbar-brand").text).to eq "ふりかえ帳"
    expect(page.at_css("#main-menu .nav-link").text).to eq "メニュー項目"
    expect(page.at_css("main .alert-success").text).to include "保存しました"
    expect(page.at_css("main p").text).to eq "画面の中身"
  end

  it "メニューの指定がなければ、メニューのボタンを表示しない" do
    render template: "layouts/application"

    expect(page.css(".navbar-toggler")).to be_empty
  end

  describe "ログイン中のメニュー" do
    it "保護者には、ホームとログアウトを表示する" do
      sign_in create(:guardian)

      render template: "layouts/application"

      links = page.css("#main-menu .nav-link").map(&:text).map(&:strip)
      expect(links).to eq %w[ホーム ログアウト]
    end

    it "先生には、ダッシュボード・生徒・固定枠・ログアウトを表示する" do
      sign_in create(:teacher)

      render template: "layouts/application"

      links = page.css("#main-menu .nav-link").map(&:text).map(&:strip)
      expect(links).to eq %w[ダッシュボード 生徒 固定枠 ログアウト]
    end

    it "ログアウトは DELETE で送る" do
      sign_in create(:guardian)

      render template: "layouts/application"

      form = page.at_css("#main-menu form")
      expect(form["action"]).to eq "/logout"
      expect(form.at_css("input[name=_method]")["value"]).to eq "delete"
    end
  end
end
