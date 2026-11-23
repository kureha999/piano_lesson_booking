# 振替ルールを保存する（T-08）。行がない状態で同時に保存されたときは、主キー（id = 1）の重複を DB が止める。
# そのときは、エラーとして扱い、もう一度保存してもらう。
#
# 使い方：
#   SaveMakeupRule.call(rule)   # 保存できたか（できなかったときは、rule.errors にエラーが入る）
class SaveMakeupRule
  def self.call(rule)
    rule.save
  rescue ActiveRecord::RecordNotUnique
    rule.errors.add(:base, "ほかの画面で同時に保存されました。もう一度お試しください")
    false
  end
end
