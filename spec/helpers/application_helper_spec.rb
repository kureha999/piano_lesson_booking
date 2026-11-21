require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#flash_class" do
    it "notice は成功（緑）、alert はエラー（赤）の見た目にする" do
      expect(helper.flash_class(:notice)).to eq "alert-success"
      expect(helper.flash_class("alert")).to eq "alert-danger"
    end

    it "それ以外の種類は情報（青）の見た目にする" do
      expect(helper.flash_class(:other)).to eq "alert-info"
    end
  end

  describe "#field_error" do
    let(:model_class) do
      Class.new do
        include ActiveModel::Model

        attr_accessor :name

        validates :name, presence: true

        def self.name = "Sample"
      end
    end

    it "エラーがある項目は、日本語のメッセージを表示する" do
      record = model_class.new
      record.validate

      html = helper.field_error(record, :name)

      expect(html).to include "invalid-feedback"
      expect(html).to include "を入力してください"
    end

    it "エラーがない項目は、何も表示しない" do
      record = model_class.new(name: "山田")
      record.validate

      expect(helper.field_error(record, :name)).to be_nil
    end
  end
end
