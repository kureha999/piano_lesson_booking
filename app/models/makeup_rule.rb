# 振替ルール。先生が設定する4項目（README 12-2）。教室に1行だけ（id = 1、DB の CHECK 制約で守る）。
# 行がない間は、初期値（テーブルの列の初期値）のまま動く。保存すると id = 1 の行ができ、2回目以降は同じ行を更新する。
class MakeupRule < ApplicationRecord
  SINGLETON_ID = 1

  validates :monthly_limit, :valid_days, :absence_deadline_hours, :reservation_deadline_days,
    presence: true,
    numericality: { only_integer: true, greater_than_or_equal_to: 0, allow_nil: true }

  # いまのルール。行がなければ、初期値が入った未保存のルールを返す
  def self.current
    find_by(id: SINGLETON_ID) || new(id: SINGLETON_ID)
  end
end
