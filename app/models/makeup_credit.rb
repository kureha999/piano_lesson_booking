# 振替権。欠席1回に1つ付き、期限（expires_on）までの振替枠の予約に使う（README 12-2）。
# 状態（未使用・予約済み・使用済み・期限切れ）は保存せず、予約と期限から判定する（README 12-6）。
class MakeupCredit < ApplicationRecord
  belongs_to :student
  belongs_to :absence

  # 予約の履歴を残すため、予約がある振替権は削除できない（キャンセルした予約も含む）
  has_many :makeup_reservations, dependent: :restrict_with_error

  # 有効な予約（キャンセルされていない予約）。振替権1つにつき、多くても1つ
  has_one :active_reservation, -> { active }, class_name: "MakeupReservation", inverse_of: :makeup_credit

  validates :expires_on, presence: true
  validates :absence_id, uniqueness: { message: "にはすでに振替権が付いています" }, allow_nil: true
  validate :student_must_be_the_absent_student

  # 状態ごとのスコープ。判定は README 12-6「振替権の状態の判定」のとおり。いまの日時（now）は、テストなどで指定できる
  #   未使用　：有効な予約がなく、今日が期限（expires_on）以前
  #   予約済み：有効な予約があり、振替枠の開始日時がまだ来ていない
  #   使用済み：有効な予約があり、振替枠の開始日時を過ぎた（振替レッスンを欠席した場合も含む）
  #   期限切れ：有効な予約がなく、今日が期限を過ぎた
  # 状態は保存しない。日付が変わるたびに書き換える処理が要らず、データの食い違いも起きない。
  scope :unused, ->(now = Time.current) { without_active_reservation.where(expires_on: today_of(now)..) }
  scope :expired, ->(now = Time.current) { without_active_reservation.where(expires_on: ...today_of(now)) }
  scope :reserved, ->(now = Time.current) { with_active_reservation_in_slots_where("makeup_slots.starts_at > ?", now) }
  scope :used, ->(now = Time.current) { with_active_reservation_in_slots_where("makeup_slots.starts_at <= ?", now) }

  # （上の4つの部品）有効な予約がない振替権／有効な予約が、条件に合う振替枠にある振替権
  scope :without_active_reservation, -> { where.not(id: MakeupReservation.active.select(:makeup_credit_id)) }
  scope :with_active_reservation_in_slots_where, lambda { |condition, now|
    where(id: MakeupReservation.active.joins(:makeup_slot).where(condition, now).select(:makeup_credit_id))
  }

  # 今日の日付（日本時間）
  def self.today_of(now)
    now.in_time_zone.to_date
  end

  # この振替権の状態。:unused（未使用）、:reserved（予約済み）、:used（使用済み）、:expired（期限切れ）
  def status(now = Time.current)
    reservation = active_reservation
    if reservation.nil?
      expires_on < self.class.today_of(now) ? :expired : :unused
    else
      reservation.makeup_slot.starts_at > now ? :reserved : :used
    end
  end

  private

  # 振替権の生徒は、欠席した生徒と同じであること
  def student_must_be_the_absent_student
    absent_student_id = absence&.lesson_slot&.student_id
    return if student_id.blank? || absent_student_id.blank?

    errors.add(:student, "は欠席した生徒と同じである必要があります") if student_id != absent_student_id
  end
end
