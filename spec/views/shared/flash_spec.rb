require "rails_helper"

RSpec.describe "shared/_flash", type: :view do
  let(:page) { Nokogiri::HTML5.fragment(rendered) }

  it "notice と alert を、種類に応じた見た目で表示する" do
    flash[:notice] = "保存しました"
    flash[:alert] = "保存できませんでした"

    render partial: "shared/flash"

    expect(page.at_css(".alert.alert-success").text).to include "保存しました"
    expect(page.at_css(".alert.alert-danger[role=alert]").text).to include "保存できませんでした"
  end

  it "flash がないときは何も表示しない" do
    render partial: "shared/flash"

    expect(page.css(".alert")).to be_empty
  end
end
