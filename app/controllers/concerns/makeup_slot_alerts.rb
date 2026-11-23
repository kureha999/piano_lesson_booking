# 選んだ振替枠を予約できなかったときのメッセージ（P-02 に戻すときに表示する）。
# 欠席する流れ（AbsencesController）と、未使用の振替権から選ぶ流れ（MakeupReservationsController）で共通。
module MakeupSlotAlerts
  extend ActiveSupport::Concern

  private

  # 先に予約されて埋まった場合は、その旨を伝える
  def slot_alert(reason)
    return "選んだ枠は予約が埋まりました。ほかの枠を選んでください。" if reason == :full

    "選んだ枠は予約できなくなりました。ほかの枠を選んでください。"
  end
end
