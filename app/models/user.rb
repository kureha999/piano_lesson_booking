# 先生と保護者。role で区別する。生徒（Student）はログインしないので、User ではない。
class User < ApplicationRecord
  # ログインは先生と保護者だけで、保護者は先生の招待で登録するため、:registerable は使わない
  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  # 保護者に属する生徒。生徒がいる間は、保護者を削除できない
  has_many :students, foreign_key: :guardian_id, inverse_of: :guardian, dependent: :restrict_with_error

  enum :role, { guardian: 0, teacher: 1 }, default: :guardian

  validates :name, presence: true
  # 先生は1人だけ。同時操作での二重登録は、DB の部分一意インデックスで防ぐ
  validates :role, uniqueness: { message: "の先生はすでに登録されています" }, if: :teacher?
end
