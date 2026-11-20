require "rails_helper"

RSpec.describe "FactoryBot の設定" do
  it "create・build などを FactoryBot. なしで呼べる" do
    expect(self).to respond_to(:create, :build, :build_stubbed, :attributes_for)
  end

  it "spec/factories を読み込む設定になっている" do
    expect(FactoryBot.definition_file_paths).to include(Rails.root.join("spec/factories"))
  end

  it "定義した factory で create(:名前) が使える" do
    FactoryBot.define do
      factory :sample_record, class: "Hash" do
        initialize_with { { name: "テスト" } }
        to_create { |_instance| }
      end
    end

    expect(create(:sample_record)).to eq({ name: "テスト" })
  ensure
    FactoryBot.factories.clear
    FactoryBot.reload
  end
end
