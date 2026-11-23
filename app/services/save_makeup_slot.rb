# 振替枠を保存する（T-07）。検証のあと、保存の直前に同じ時間の枠が登録されたときは、DB の排他制約が止める。
# そのときも、モデルの検証と同じ「重なり」のエラーとして扱う（README 12-6）。
#
# 使い方：
#   SaveMakeupSlot.call(slot)   # 保存できたか（できなかったときは、slot.errors にエラーが入る）
class SaveMakeupSlot
  def self.call(slot)
    slot.save
  rescue ActiveRecord::StatementInvalid => e
    raise unless e.cause.is_a?(PG::ExclusionViolation)

    slot.errors.add(:base, "同じ時間に、ほかの振替枠が登録されました。時間を変えて、もう一度お試しください")
    false
  end
end
