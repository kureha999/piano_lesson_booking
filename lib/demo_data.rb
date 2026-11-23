# 動作確認とデモ動画のための、架空の教室のデータを作る（bin/rails db:seed から呼ぶ）。
#
#   bin/rails db:seed
#
# 作るもの：先生1人、保護者3人と生徒4人（兄弟を含む）、固定枠、振替枠、振替ルール、
#   欠席（振替権あり・振替を予約ずみ・使用ずみ・キャンセルずみ・当日欠席）。
#   すべての画面（P-01〜P-05、T-01〜T-08）にデータが表示される。
#
# 何度実行しても同じ状態になる：実行のたびに、ふりかえ帳のデータをすべて消して、作り直す。
#   日付は、実行した日の「今週」を基準に作る（毎回、今週・来週の予定が表示される）。
#
# 安全のため、次の場合は何も作らず、DemoData::Refused のエラーにする。
#   - デモ用ではないユーザー（@demo.example.com 以外のメールアドレス）がいる（自分で登録したデータを消さないため）
#   - 本番環境（環境変数 DEMO_SEED=1 を付けたときだけ作れる。架空のアカウントを、うっかり本番に作らないため）
#
# すべて架空の人物・データ。パスワードは、デモ用の固定値（README に記載）。
class DemoData
  class Refused < StandardError; end

  DOMAIN = "demo.example.com"
  PASSWORD = "password123"

  TEACHER = { name: "佐藤 美咲", email: "teacher@#{DOMAIN}" }.freeze

  def self.load(today: Date.current, env: Rails.env, allow_production: ENV["DEMO_SEED"] == "1")
    new(today: today, env: env, allow_production: allow_production).load
  end

  def initialize(today:, env:, allow_production:)
    @monday = today.beginning_of_week(:monday) # 今週の月曜日。ここからの日数で、日付を決める
    @env = env.to_s
    @allow_production = allow_production
  end

  def load
    guard!
    ActiveRecord::Base.transaction do
      reset!
      create_rule
      create_teacher
      create_families
      create_makeup_slots
      create_history
    end
    summary
  end

  private

  attr_reader :monday

  # 今週の月曜日から数えて、n 日目の日付（-5 なら、先週の水曜日）
  def day(offset)
    monday + offset
  end

  def at(date, hour, minute = 0)
    Time.zone.local(date.year, date.month, date.day, hour, minute)
  end

  def guard!
    if @env == "production" && !@allow_production
      raise Refused, "本番環境では、デモデータを作りません（作る場合は、環境変数 DEMO_SEED=1 を付けます）。"
    end
    return unless User.where.not("email LIKE ?", "%@#{DOMAIN}").exists?

    raise Refused, "デモ用ではないユーザーがいるため、デモデータを作りません（作り直しで、登録ずみのデータが消えてしまうため）。"
  end

  # ふりかえ帳のデータをすべて消す（外部キーの順）。guard! で、消してよい DB であることは確かめてある
  def reset!
    [ MakeupReservation, MakeupCredit, Absence, MakeupSlot, LessonSlot, Student, User, MakeupRule ].each(&:delete_all)
  end

  # 行を作る（保存して、「③ 振替ルールを確認する」を完了にする）。値は初期値のまま
  def create_rule
    @rule = MakeupRule.current
    @rule.save!
  end

  def create_teacher
    User.create!(**TEACHER, password: PASSWORD, role: :teacher)
  end

  # 保護者・生徒・固定枠。固定枠は先生が1人なので、時間が重ならないようにする
  def create_families
    @students = {}
    @lesson_slots = {}
    [
      { guardian: "山田 花子", email: "hanako@#{DOMAIN}", children: [ [ :hinata, "ひなた", 3, "16:00", "16:30" ], [ :sota, "そうた", 3, "16:30", "17:00" ] ] },
      { guardian: "鈴木 一郎", email: "ichiro@#{DOMAIN}", children: [ [ :yuki, "ゆうき", 2, "16:00", "16:30" ] ] },
      { guardian: "田中 恵", email: "megumi@#{DOMAIN}", children: [ [ :misaki, "みさき", 4, "17:00", "17:30" ] ] }
    ].each do |family|
      guardian = User.create!(name: family[:guardian], email: family[:email], password: PASSWORD, role: :guardian)
      family[:children].each do |key, name, wday, start_time, end_time|
        student = Student.create!(guardian: guardian, name: name)
        @students[key] = student
        @lesson_slots[key] = LessonSlot.create!(student: student, wday: wday, start_time: start_time, end_time: end_time, starts_on: day(-28))
      end
    end
  end

  # 振替枠：土曜日 10:00（定員2）と月曜日 15:00（定員1）。先週から再来週まで
  def create_makeup_slots
    @makeup_slots = {
      last_sat: slot_at(day(-2), 10, 2),
      this_sat: slot_at(day(5), 10, 2),
      next_mon: slot_at(day(7), 15, 1),
      next_sat: slot_at(day(12), 10, 2),
      mon_after_next: slot_at(day(14), 15, 1),
      sat_after_next: slot_at(day(19), 10, 2)
    }
  end

  def slot_at(date, hour, capacity)
    MakeupSlot.create!(starts_at: at(date, hour), ends_at: at(date, hour, 30), capacity: capacity)
  end

  # 欠席・振替権・振替予約。連絡した日時を指定して、実際のルールで振替権を付けるかを判定する（MakeupCreditEligibility）
  def create_history
    # ひなた：先週の欠席は、土曜日の振替を受けた（使用ずみ）。今週の欠席は、来週土曜日に振替を予約ずみ（キャンセルできる）
    _, last_week_credit = report(:hinata, day(-5))
    reserve(last_week_credit, @makeup_slots[:last_sat])
    _, this_week_credit = report(:hinata, day(2))
    reserve(this_week_credit, @makeup_slots[:next_sat])

    # そうた：先週の欠席の振替権は未使用。今週土曜日の予約はキャンセルした（履歴）
    _, sota_credit = report(:sota, day(-5))
    reserve(sota_credit, @makeup_slots[:this_sat], canceled_at: at(day(-3), 12))

    # ゆうき：先週の欠席の振替権は未使用。今週の欠席は、レッスンの1時間前の連絡（当日欠席。振替権は付かない）
    report(:yuki, day(-6))
    report(:yuki, day(1), reported_at: at(day(1), 15))

    # みさき：今週の欠席。振替は、まだ選んでいない（振替権は未使用）
    report(:misaki, day(3))
  end

  # 欠席を登録する。レッスンの前日の昼に連絡したことにする（reported_at で変えられる）。戻り値は [欠席, 振替権（付かなければ nil）]
  # 登録した順に判定するので、月の上限は、連絡した順に数えられる
  def report(student_key, lesson_on, reported_at: nil)
    lesson_slot = @lesson_slots.fetch(student_key)
    student = @students.fetch(student_key)
    reported_at ||= at(lesson_on - 1, 12)
    absence = Absence.new(lesson_slot: lesson_slot, lesson_on: lesson_on, reported_by: student.guardian,
      created_at: reported_at, updated_at: reported_at)
    eligibility = MakeupCreditEligibility.new(absence, now: reported_at, rule: @rule)
    reason = eligibility.no_credit_reason # 保存する前に判定する（保存した後は、月の上限の数に、この欠席が入ってしまう）
    absence.no_credit_reason = reason
    absence.save!(validate: false) # 過去の日付の欠席も作るため、「レッスン開始前」の確認は省く
    credit = reason ? nil : MakeupCredit.create!(student: student, absence: absence, expires_on: eligibility.expires_on, created_at: reported_at)
    [ absence, credit ]
  end

  def reserve(credit, makeup_slot, canceled_at: nil)
    MakeupReservation.create!(makeup_credit: credit, makeup_slot: makeup_slot, student: credit.student, canceled_at: canceled_at)
  end

  def summary
    {
      teacher: TEACHER[:email], guardians: User.guardian.order(:id).pluck(:email), password: PASSWORD,
      students: Student.count, lesson_slots: LessonSlot.count, makeup_slots: MakeupSlot.count,
      absences: Absence.count, credits: MakeupCredit.count, reservations: MakeupReservation.count
    }
  end
end
