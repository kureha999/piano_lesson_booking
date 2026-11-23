# 欠席・振替のメールを、先生と保護者に送る（F-12）。送るのは Active Job（deliver_later）なので、
# 画面の応答を待たせず、メールサーバーの不調で確定が失敗することもない。
# 確定（トランザクションの完了）の後に呼ぶ。失敗した操作では呼ばない。
#
# 宛先は、教室の先生（いなければ送らない）と、その生徒の保護者。
#
# 使い方：
#   MakeupNotifications.absence_received(absence)    # 欠席受付（振替を予約したときは、振替確定も同じメールで伝える）
#   MakeupNotifications.makeup_confirmed(reservation) # 振替確定（未使用の振替権から、あとで予約したとき）
#   MakeupNotifications.makeup_canceled(reservation)  # 振替予約のキャンセル
class MakeupNotifications
  def self.absence_received(absence)
    recipients_for(absence.lesson_slot.student).each { |user| MakeupMailer.absence_received(absence, user).deliver_later }
  end

  def self.makeup_confirmed(reservation)
    recipients_for(reservation.student).each { |user| MakeupMailer.makeup_confirmed(reservation, user).deliver_later }
  end

  def self.makeup_canceled(reservation)
    recipients_for(reservation.student).each { |user| MakeupMailer.makeup_canceled(reservation, user).deliver_later }
  end

  # 先生と、生徒の保護者（メールアドレスは、ユーザーごとに一意）
  def self.recipients_for(student)
    [ User.teacher.first, student.guardian ].compact
  end
  private_class_method :recipients_for
end
