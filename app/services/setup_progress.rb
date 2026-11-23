# 先生の初期設定（README 5-4・12-5③）が、どこまで終わっているか。T-01 ダッシュボードに、残りの手順を表示するために使う。
#
# 手順（画面遷移図③の順）：
#   ① 生徒を登録する          生徒が1人以上いれば完了
#   ② 固定枠を設定する        固定枠が1つ以上あれば完了
#   ② 振替枠を登録する        振替枠が1つ以上あれば完了
#   ③ 振替ルールを確認する    振替ルールの行があれば完了（行がない間は初期値で動くが、先生が一度保存して確認するまでは未完了。README 12-6）
#
# 使い方：
#   progress = SetupProgress.new
#   progress.steps       # すべての手順（Step の配列。key・label・done?）
#   progress.remaining   # まだ終わっていない手順
#   progress.complete?   # すべて終わったか（終わったら、T-01 の手順の表示を消す）
class SetupProgress
  Step = Data.define(:key, :label, :done) do
    def done? = done
  end

  def steps
    @steps ||= [
      Step.new(key: :student, label: "① 生徒を登録する", done: Student.exists?),
      Step.new(key: :lesson_slot, label: "② 固定枠を設定する", done: LessonSlot.exists?),
      Step.new(key: :makeup_slot, label: "② 振替枠を登録する", done: MakeupSlot.exists?),
      Step.new(key: :makeup_rule, label: "③ 振替ルールを確認する", done: MakeupRule.exists?)
    ]
  end

  def remaining
    steps.reject(&:done?)
  end

  def complete?
    remaining.empty?
  end
end
