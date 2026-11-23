require "rails_helper"

RSpec.describe ReserveMakeupSlot do
  let(:now) { Time.zone.local(2026, 11, 2, 9, 0) }
  let(:student) { create(:student) }
  let(:credit) { create_credit_for(student, Date.new(2026, 11, 11)) } # 期限は 12/11
  let(:slot) { create_makeup_slot(Date.new(2026, 11, 16)) }

  # 時刻を合わせた後に、振替権を作る（欠席は、レッスンが始まる前でないと登録できない）
  before do
    travel_to now
    credit
  end

  def reserve(makeup_credit = credit, makeup_slot = slot)
    described_class.call(makeup_credit: makeup_credit, makeup_slot: makeup_slot)
  end

  describe "予約できるとき" do
    it "予約を作り、生徒は振替権を持つ生徒になる" do
      result = reserve

      expect(result).to be_success
      expect(result.reason).to be_nil
      expect(result.reservation).to be_persisted
      expect(result.reservation).to have_attributes(makeup_credit: credit, makeup_slot: slot, student: student, canceled_at: nil)
    end

    it "予約しても、枠の予約数が1つ増える" do
      expect { reserve }.to change(slot, :reserved_count).from(0).to(1)
    end
  end

  describe "予約できないとき" do
    it "定員に達した枠には、予約しない（先着順。README 12-2）" do
      reserve
      other = create_credit_for(create(:student), Date.new(2026, 11, 9))

      result = reserve(other)

      expect(result).not_to be_success
      expect(result.reason).to eq :full
      expect(result.reservation).to be_nil
      expect(MakeupReservation.count).to eq 1
    end

    it "定員2なら、2人目まで予約できる" do
      two = create_makeup_slot(Date.new(2026, 11, 17), capacity: 2)
      other = create_credit_for(create(:student), Date.new(2026, 11, 9))

      expect(reserve(credit, two)).to be_success
      expect(reserve(other, two)).to be_success
    end

    it "期限・締切など、ほかの理由でも予約しない（理由は MakeupSlotAvailability と同じ）" do
      too_late = create_makeup_slot(Date.new(2026, 12, 12))

      result = reserve(credit, too_late)

      expect(result.reason).to eq :out_of_period
      expect(MakeupReservation.count).to eq 0
    end

    it "同じ振替権で、2回目の予約はできない（再振替はできない）" do
      reserve

      result = reserve(credit, create_makeup_slot(Date.new(2026, 11, 17)))

      expect(result.reason).to eq :credit_used
      expect(MakeupReservation.count).to eq 1
    end

    it "確認の後に同じ振替権で予約された場合（モデルの検証）も、理由つきで返す" do
      allow_any_instance_of(MakeupSlotAvailability).to receive(:unavailable_reason).and_return(nil) # rubocop:disable RSpec/AnyInstance
      reserve

      result = reserve(credit, create_makeup_slot(Date.new(2026, 11, 17)))

      expect(result.reason).to eq :credit_used
      expect(result.reservation).to be_nil
    end

    it "確認も検証も通り抜けても（DB の部分一意インデックス）、理由つきで返す" do
      allow_any_instance_of(MakeupSlotAvailability).to receive(:unavailable_reason).and_return(nil) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(MakeupReservation).to receive(:valid?).and_return(true) # rubocop:disable RSpec/AnyInstance
      reserve

      result = reserve(credit, create_makeup_slot(Date.new(2026, 11, 17)))

      expect(result.reason).to eq :credit_used
      expect(result.reservation).to be_nil
    end
  end

  describe "同時に予約したとき" do
    it "予約の前に、振替枠の行をロックする" do
      allow(slot).to receive(:with_lock).and_call_original

      reserve

      expect(slot).to have_received(:with_lock)
    end

    # 実際に複数のスレッドから予約する。トランザクションをまたぐので、テストごとのロールバックは使わず、終わったら消す
    context "複数のスレッドから予約する" do
      self.use_transactional_tests = false

      after do
        [ MakeupReservation, MakeupCredit, Absence, LessonSlot, Student, MakeupSlot, MakeupRule ].each(&:delete_all)
        User.delete_all
      end

      # N+1 の検出は外す：複数のスレッドから同じ処理を同時に実行する
      it "定員1の枠に4人が同時に予約しても、予約できるのは1人だけ", prosopite: false do
        credits = [ credit ] + [ 9, 10, 12 ].map { |day| create_credit_for(create(:student), Date.new(2026, 11, day)) }
        slot_id = slot.id
        # 確認と保存の間に待ちを入れて、ロックがなければ、全員が「空きあり」と判断する状況にする
        allow_any_instance_of(MakeupSlotAvailability).to receive(:unavailable_reason).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
          original.call(*args).tap { sleep 0.2 }
        end

        results = credits.map do |makeup_credit|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              described_class.call(makeup_credit: MakeupCredit.find(makeup_credit.id), makeup_slot: MakeupSlot.find(slot_id))
            end
          end
        end.map(&:value)

        expect(results.count(&:success?)).to eq 1
        expect(results.reject(&:success?).map(&:reason)).to all(eq :full)
        expect(MakeupReservation.active.count).to eq 1
      end

      it "同じ振替権で、別々の枠に同時に予約しても、有効な予約は1つだけ" do
        other_slot = create_makeup_slot(Date.new(2026, 11, 17))
        slot_ids = [ slot.id, other_slot.id ]

        results = slot_ids.map do |id|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              described_class.call(makeup_credit: MakeupCredit.find(credit.id), makeup_slot: MakeupSlot.find(id))
            end
          end
        end.map(&:value)

        expect(results.count(&:success?)).to eq 1
        expect(results.reject(&:success?).map(&:reason)).to eq [ :credit_used ]
        expect(MakeupReservation.active.count).to eq 1
      end
    end
  end
end
