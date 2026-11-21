# 固定枠の登録・変更のフォーム（T-05）。
#
# 登録：生徒・曜日・開始時刻・終了時刻・適用開始日から、新しい固定枠を作る。
# 変更：曜日や時間を変えるときは、枠を上書きしない。今の枠に適用終了日（適用開始日の前日）を入れて、新しい枠を作る。
#   過去の欠席が指している枠の曜日・時間が変わると、履歴が壊れるため（README 12-6「設計の方針」）。
#   2つの枠を1つのトランザクションで保存するので、Controller や Model に書かず、このクラスにまとめる。
#   曜日・時間が変わらないときは、何も保存しない。
class LessonSlotForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  # 枠のエラーを、フォームのどの項目のエラーにするか（それ以外は、フォーム全体のエラー）
  FIELDS = %i[wday start_time end_time starts_on].freeze
  private_constant :FIELDS

  attribute :student_id, :integer
  attribute :wday, :integer
  attribute :start_time, :string # "16:00" の形式
  attribute :end_time, :string
  attribute :starts_on, :date    # 登録：適用開始日。変更：新しい枠の適用開始日

  attr_reader :lesson_slot # 変更のとき、今の枠。保存後は、保存した（新しい）枠

  # フォームのパラメーター名（lesson_slot[wday] など）と、属性名の訳（activemodel.attributes.lesson_slot）に使う
  def self.model_name
    ActiveModel::Name.new(self, nil, "LessonSlot")
  end

  # 今の枠から、変更用のフォームを作る。新しい枠の適用開始日は、今日（今の枠の開始日より後にする）
  def self.for(slot)
    new(lesson_slot: slot, student_id: slot.student_id, wday: slot.wday,
      start_time: format_time(slot.start_time), end_time: format_time(slot.end_time),
      starts_on: [ Date.current, slot.starts_on + 1 ].max)
  end

  def self.format_time(time)
    time.strftime("%H:%M")
  end

  def initialize(lesson_slot: nil, **attributes)
    @lesson_slot = lesson_slot
    @changed = true
    super(**attributes)
  end

  # 変更のとき、保存済みの枠を変更しようとしているか
  def persisted?
    lesson_slot&.persisted? || false
  end

  # 変更で、曜日・時間が今の枠と変わらず、何も保存しなかったか
  def unchanged?
    !@changed
  end

  def student
    @student ||= Student.find_by(id: student_id)
  end

  def save
    persisted? ? change_slot : create_slot
  end

  private

  def create_slot
    slot = build_slot(student)
    return invalid_with(slot) unless slot.valid? && student_chosen?

    slot.save!
    @lesson_slot = slot
    true
  end

  def change_slot
    current = lesson_slot
    @student = current.student
    unless schedule_changed?(current)
      @changed = false
      return true
    end
    return false unless valid_starts_on?(current)

    saved = false
    ActiveRecord::Base.transaction do
      # 先に今の枠を終わらせてから、新しい枠を検証する（今の枠と重なって見えないように）
      current.update!(ends_on: [ current.ends_on, starts_on - 1 ].compact.min)
      slot = build_slot(current.student)
      if slot.valid?
        slot.save!
        @lesson_slot = slot
        saved = true
      else
        invalid_with(slot)
        raise ActiveRecord::Rollback
      end
    end
    current.reload unless saved
    saved
  end

  def build_slot(student)
    LessonSlot.new(student: student, wday: wday, start_time: start_time, end_time: end_time, starts_on: starts_on)
  end

  def student_chosen?
    return true if student

    errors.add(:student_id, "を選んでください")
    false
  end

  # 新しい枠の適用開始日は、今の枠の適用開始日より後でなければ、今の枠に適用終了日を入れられない
  def valid_starts_on?(current)
    if starts_on.nil?
      errors.add(:starts_on, "を入力してください")
    elsif starts_on <= current.starts_on
      errors.add(:starts_on, "は、今の枠の適用開始日（#{current.starts_on.strftime('%Y年%-m月%-d日')}）より後にしてください")
    end
    errors.empty?
  end

  def schedule_changed?(current)
    wday != current.wday ||
      start_time.to_s[0, 5] != self.class.format_time(current.start_time) ||
      end_time.to_s[0, 5] != self.class.format_time(current.end_time)
  end

  # 枠のエラーを、フォームの項目に移す。常に false を返す
  def invalid_with(slot)
    slot.valid?
    slot.errors.each do |error|
      next if error.attribute == :student

      errors.add(FIELDS.include?(error.attribute) ? error.attribute : :base, error.message)
    end
    student_chosen?
    false
  end
end
