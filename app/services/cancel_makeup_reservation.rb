# 振替予約をキャンセルする（F-10、README 12-2）。行は消さず、canceled_at に日時を入れる（履歴が残る）。
# キャンセルすると、振替権は未使用に戻り（状態は保存せず、予約から判定する）、同じ振替権でほかの枠を予約できる。
#
# 使い方：
#   result = CancelMakeupReservation.call(reservation)
#   result.success?   # キャンセルできたか
#   result.reason     # 失敗した理由。:already_canceled（すでにキャンセルずみ）、:deadline_passed（締切を過ぎた・枠が始まった）
#
# 締切後のキャンセルは、画面でボタンを隠すだけでなく、ここでも拒否する（サーバー側の確認）。
# 同時に2回送られても、予約の行をロックしてから確認するので、キャンセルは1回だけ行われる。
class CancelMakeupReservation
  Result = Struct.new(:reservation, :reason) do
    def success? = reason.nil?
  end

  def self.call(...) = new(...).call

  def initialize(reservation, now: Time.current)
    @reservation = reservation
    @now = now
  end

  def call
    reason = nil

    @reservation.with_lock do
      reason = failure_reason
      @reservation.update!(canceled_at: @now) unless reason
    end

    Result.new(@reservation, reason)
  end

  private

  def failure_reason
    return :already_canceled if @reservation.canceled?

    :deadline_passed unless @reservation.cancelable?(@now)
  end
end
