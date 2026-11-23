module AbsencesHelper
  # P-02 で、予約できる枠がないときに表示する理由。reason は MakeupSlotAvailability#unavailable_reason の値。
  # 先生が登録した枠がそもそもないときは、reason_counts が空になるので、別の文言を使う。
  # period は、受講できる期間（Date の Range）。:already_started・:credit_used は、P-02 では表示しない。
  def makeup_unavailable_message(reason, period)
    case reason
    when :out_of_period
      "受講できる期間（#{japanese_date(period.begin)}〜#{japanese_date(period.end)}）の外の枠があります。"
    when :deadline_passed then "予約の締切を過ぎた枠があります。"
    when :full then "定員に達した枠があります。"
    when :conflict then "ほかのレッスンと時間が重なる枠があります。"
    end
  end

  # 「6月13日（土） 15:00〜15:30」
  def makeup_slot_text(slot)
    "#{japanese_date_with_wday(slot.starts_at.to_date)} #{slot.starts_at.strftime('%H:%M')}〜#{slot.ends_at.strftime('%H:%M')}"
  end
end
