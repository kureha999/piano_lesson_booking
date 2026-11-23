# 欠席連絡の確定（P-03 の「確定する」）。欠席・振替権・振替予約を、1つのトランザクションでまとめて作る（F-08・F-09）。
#
# 使い方：
#   result = ConfirmAbsence.call(lesson_slot: slot, lesson_on: date, reported_by: user, makeup_slot: makeup_slot_or_nil)
#   result.success?        # 確定できたか
#   result.absence         # 登録した欠席
#   result.makeup_credit   # 付けた振替権（付かなかったときは nil）
#   result.reservation     # 振替予約（「振替は後で選ぶ」のときや、振替権が付かないときは nil）
#   result.reason          # 失敗した理由（成功のときは nil）
#     :invalid     欠席を登録できない（すでに欠席ずみ・もう始まったレッスンなど）
#     :no_credit   振替枠を選んだが、確定の時点で振替権が付かなくなっていた（締切を過ぎた・月の上限に達した）
#     それ以外      選んだ振替枠を予約できない理由（MakeupSlotAvailability#unavailable_reason と同じ。:full など）
#
# 失敗したときは、何も登録しない（欠席だけが登録されることはない）。
# 欠席の登録（RegisterAbsence：生徒の行をロック）→ 振替枠の予約（ReserveMakeupSlot：振替枠の行をロック）の順に行う。
class ConfirmAbsence
  Result = Struct.new(:absence, :makeup_credit, :reservation, :reason) do
    def success? = reason.nil?
  end

  def self.call(...) = new(...).call

  def initialize(lesson_slot:, lesson_on:, reported_by:, makeup_slot: nil)
    @lesson_slot = lesson_slot
    @lesson_on = lesson_on
    @reported_by = reported_by
    @makeup_slot = makeup_slot
  end

  def call
    result = nil

    ActiveRecord::Base.transaction do
      result = confirm
      raise ActiveRecord::Rollback unless result.success?
    end

    result
  end

  private

  def confirm
    registered = RegisterAbsence.call(lesson_slot: @lesson_slot, lesson_on: @lesson_on, reported_by: @reported_by)
    return Result.new(registered.absence, nil, nil, :invalid) unless registered.success?
    return Result.new(registered.absence, registered.makeup_credit, nil, nil) if @makeup_slot.nil?
    return Result.new(registered.absence, nil, nil, :no_credit) if registered.makeup_credit.nil?

    reserved = ReserveMakeupSlot.call(makeup_credit: registered.makeup_credit, makeup_slot: @makeup_slot)
    Result.new(registered.absence, registered.makeup_credit, reserved.reservation, reserved.reason)
  end
end
