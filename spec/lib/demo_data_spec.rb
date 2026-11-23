require "rails_helper"
require "rake"

# N+1 の検出は外す：デモデータの作成は、1件ずつ検証しながら保存する処理で、画面ではない（画面の N+1 は demo_data_screens_spec で確認する）
RSpec.describe DemoData, prosopite: false do
  # 2026年11月11日（水）。今週は 11/9（月）〜11/15（日）
  let(:today) { Date.new(2026, 11, 11) }

  def snapshot
    {
      users: User.order(:email).pluck(:email, :role, :name),
      students: Student.order(:name).pluck(:name),
      lesson_slots: LessonSlot.joins(:student).order("students.name").pluck("students.name", :wday, :start_time, :end_time, :starts_on).map { |row| row.map(&:to_s) },
      makeup_slots: MakeupSlot.order(:starts_at).pluck(:starts_at, :capacity),
      absences: Absence.joins(lesson_slot: :student).order("students.name", :lesson_on).pluck("students.name", :lesson_on, :no_credit_reason),
      credits: MakeupCredit.order(:expires_on).pluck(:expires_on),
      reservations: MakeupReservation.joins(:makeup_slot).order("makeup_slots.starts_at").pluck("makeup_slots.starts_at", :canceled_at)
    }
  end

  describe ".load" do
    it "先生1人、保護者3人、生徒4人（兄弟を含む）、固定枠、振替枠、振替ルール、欠席・振替予約を作る" do
      result = described_class.load(today: today)

      expect(User.teacher.pluck(:email)).to eq [ "teacher@demo.example.com" ]
      expect(User.guardian.count).to eq 3
      expect(Student.count).to eq 4
      expect(Student.group(:guardian_id).count.values.sort).to eq [ 1, 1, 2 ] # 兄弟がいる家庭
      expect(LessonSlot.count).to eq 4
      expect(MakeupSlot.count).to eq 6
      expect(MakeupRule.count).to eq 1
      expect(Absence.count).to eq 6
      expect(result).to include(teacher: "teacher@demo.example.com", password: "password123", students: 4)
    end

    it "すべて架空のデータ（メールアドレスは demo.example.com）" do
      described_class.load(today: today)

      expect(User.pluck(:email)).to all(end_with("@demo.example.com"))
    end

    it "欠席は、振替権あり・使用ずみ・予約ずみ・キャンセルずみ・当日欠席の例をそろえる" do
      described_class.load(today: today)
      travel_to Time.zone.local(2026, 11, 11, 10, 0)

      expect(MakeupCredit.all.map(&:status).tally).to eq(used: 1, reserved: 1, unused: 3)
      expect(Absence.after_deadline.count).to eq 1 # 当日欠席（ゆうき）
      expect(MakeupReservation.where.not(canceled_at: nil).count).to eq 1
      expect(MakeupReservation.active.count).to eq 2
    end

    it "兄弟のそうたとひなたは、同じ保護者に属する" do
      described_class.load(today: today)

      expect(Student.find_by!(name: "ひなた").guardian).to eq Student.find_by!(name: "そうた").guardian
    end

    it "固定枠は、先生が1人なので重ならず、振替枠も固定枠と重ならない（モデルの検証を通る）" do
      described_class.load(today: today)

      expect(LessonSlot.all).to all(be_valid)
      expect(MakeupSlot.all).to all(be_valid)
    end

    it "何度実行しても、同じ状態になる" do
      described_class.load(today: today)
      first = snapshot

      described_class.load(today: today)

      expect(snapshot).to eq first
    end

    it "実行した日の「今週」を基準に作る（別の日に実行すると、日付が移る）" do
      described_class.load(today: today)
      this_week = snapshot[:absences].map { |row| row[1] }

      described_class.load(today: today + 7)

      expect(snapshot[:absences].map { |row| row[1] }).to eq(this_week.map { |date| date + 7 })
    end

    it "どの曜日に実行しても、作れる（日曜日・月曜日・土曜日）" do
      [ Date.new(2026, 11, 8), Date.new(2026, 11, 9), Date.new(2026, 11, 14) ].each do |date|
        expect { described_class.load(today: date) }.not_to raise_error
        expect(Absence.count).to eq 6
      end
    end

    it "欠席は、実行した日の今週を中心に、先週・今週に作る" do
      described_class.load(today: today)

      expect(Absence.minimum(:lesson_on)).to eq Date.new(2026, 11, 3) # 先週の火曜日
      expect(Absence.maximum(:lesson_on)).to eq Date.new(2026, 11, 12) # 今週の木曜日
    end
  end

  describe "安全装置" do
    it "本番環境では、何も作らずに止まる" do
      expect { described_class.load(today: today, env: "production", allow_production: false) }.to raise_error(described_class::Refused, /本番環境/)
      expect(User.count).to eq 0
    end

    it "本番環境でも、DEMO_SEED=1 を付けたとき（allow_production）だけ作れる" do
      expect { described_class.load(today: today, env: "production", allow_production: true) }.not_to raise_error
      expect(User.count).to eq 4
    end

    it "デモ用ではないユーザーがいるときは、何も消さず・作らずに止まる" do
      real = create(:guardian, email: "real@example.com")
      student = create(:student, guardian: real)

      expect { described_class.load(today: today) }.to raise_error(described_class::Refused, /デモ用ではないユーザー/)

      expect(User.pluck(:email)).to eq [ "real@example.com" ]
      expect(Student.pluck(:id)).to eq [ student.id ]
    end

    it "途中で失敗したときは、消した分も含めて元に戻す（トランザクション）" do
      described_class.load(today: today)
      before = snapshot
      allow(MakeupSlot).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect { described_class.load(today: today) }.to raise_error(ActiveRecord::RecordInvalid)

      expect(snapshot).to eq before
    end
  end

  describe "db:seed" do
    # bin/rails db:seed を直接実行したときの、Rake の最上位のタスク
    def run_seeds_as(*top_level_tasks)
      allow(Rake.application).to receive(:top_level_tasks).and_return(top_level_tasks)
      capture_stdout { load Rails.root.join("db/seeds.rb") }
    end

    it "bin/rails db:seed を直接実行したときは、デモデータを作り、アカウントとパスワードを表示する" do
      output = run_seeds_as("db:seed")

      expect(output).to include "デモデータを作りました（すべて架空のデータです）。", "teacher@demo.example.com", "hanako@demo.example.com",
        "パスワード（共通）：password123"
      expect(User.count).to eq 4
    end

    it "db:prepare・db:setup・db:reset（新しい DB を作るとき）から読み込まれたときは、何も作らず、止まりもしない" do
      %w[db:prepare db:setup db:reset].each do |task|
        expect { run_seeds_as(task) }.not_to raise_error
      end

      expect(User.count).to eq 0
    end

    it "テストの実行中（Rake のタスクではない）は、何も作らない" do
      expect { capture_stdout { load Rails.root.join("db/seeds.rb") } }.not_to change(User, :count)
    end

    it "直接実行して、作れないときは、理由を表示して止まる（何も消さない）" do
      create(:guardian, email: "real@example.com")

      expect { run_seeds_as("db:seed") }.to raise_error(SystemExit)
      expect(User.pluck(:email)).to eq [ "real@example.com" ]
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
