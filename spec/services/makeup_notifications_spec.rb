require "rails_helper"

RSpec.describe MakeupNotifications do
  include ActiveJob::TestHelper

  let(:now) { Time.zone.local(2026, 11, 2, 9, 0) }
  let(:student) { create(:student, guardian: create(:guardian, email: "hanako@example.com")) }
  let(:credit) { create_credit_for(student, Date.new(2026, 11, 11)) }
  let(:reservation) { create(:makeup_reservation, makeup_credit: credit, makeup_slot: create_makeup_slot(Date.new(2026, 11, 16))) }

  before { travel_to now } # 欠席は、レッスンが始まる前でないと登録できない。let は、使うときに作られる

  context "先生がいるとき" do
    before { create(:teacher, email: "teacher@example.com") }

    it "欠席受付のメールを、先生と保護者の両方に、Active Job で送る" do
      expect { described_class.absence_received(credit.absence) }
        .to have_enqueued_mail(MakeupMailer, :absence_received).twice
    end

    it "振替確定・キャンセルのメールも、先生と保護者の両方に送る" do
      expect { described_class.makeup_confirmed(reservation) }.to have_enqueued_mail(MakeupMailer, :makeup_confirmed).twice
      expect { described_class.makeup_canceled(reservation) }.to have_enqueued_mail(MakeupMailer, :makeup_canceled).twice
    end

    it "実際に配信すると、先生と保護者のメールアドレスにそれぞれ1通届く" do
      perform_enqueued_jobs { described_class.absence_received(credit.absence) }

      expect(ActionMailer::Base.deliveries.flat_map(&:to)).to contain_exactly("teacher@example.com", "hanako@example.com")
    end
  end

  it "先生のアカウントがまだなければ、保護者にだけ送る" do
    expect { described_class.absence_received(credit.absence) }.to have_enqueued_mail(MakeupMailer, :absence_received).once
  end

  it "送るのは確定の後（呼んだ時点では、メールを送る仕事を積むだけ）" do
    create(:teacher)

    expect { described_class.absence_received(credit.absence) }.not_to change { ActionMailer::Base.deliveries.size }
  end
end
