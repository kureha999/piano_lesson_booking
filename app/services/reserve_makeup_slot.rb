# 振替権で、振替枠を予約する（F-09、README 12-2）。
#
# 使い方：
#   result = ReserveMakeupSlot.call(makeup_credit: credit, makeup_slot: slot)
#   result.success?       # 予約できたか
#   result.reservation    # 予約（失敗したときは nil）
#   result.reason         # 失敗した理由（MakeupSlotAvailability#unavailable_reason と同じ。成功のときは nil）
#
# 先着順で定員を守るため、振替枠の行をロックしてから、予約できるかを確かめて予約する（README 12-6）。
# ロックしている間は、同じ枠への予約が順番に処理されるので、定員を超えない。
# 同じ振替権で、別の枠へ同時に予約したときは、モデルの検証か、DB の部分一意インデックスが2つ目を止める。
class ReserveMakeupSlot
  Result = Struct.new(:reservation, :reason) do
    def success? = reason.nil?
  end

  def self.call(...) = new(...).call

  def initialize(makeup_credit:, makeup_slot:)
    @credit = makeup_credit
    @slot = makeup_slot
  end

  def call
    reservation = nil
    reason = nil

    @slot.with_lock do
      reason = MakeupSlotAvailability.new(@credit).unavailable_reason(@slot)
      reservation = MakeupReservation.create!(makeup_credit: @credit, makeup_slot: @slot, student: @credit.student) unless reason
    end

    Result.new(reservation, reason)
  rescue ActiveRecord::RecordNotUnique
    Result.new(nil, :credit_used)
  rescue ActiveRecord::RecordInvalid => e
    # 確認の後、保存の前に、同じ振替権で別の予約が確定した場合（モデルの検証が先に気づく）
    raise unless e.record.errors.include?(:makeup_credit_id)

    Result.new(nil, :credit_used)
  end
end
