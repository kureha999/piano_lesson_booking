require "rails_helper"

RSpec.describe "SimpleCov の設定" do
  it "カバレッジの測定が動いている" do
    expect(Coverage.running?).to be true
  end

  it "レポートを coverage/ に出力する" do
    expect(SimpleCov.coverage_path).to eq Rails.root.join("coverage").to_s
  end

  it "spec・config・db を対象外にしている" do
    %w[spec/rails_helper.rb config/application.rb db/schema.rb].each do |path|
      file = SimpleCov::SourceFile.new(Rails.root.join(path).to_s, [ nil ])
      expect(SimpleCov.filtered([ file ])).to be_empty, "#{path} が対象外になっていない"
    end
  end
end
