# bin/rails db:seed：動作確認とデモ動画のための、架空の教室のデータを作る（lib/demo_data.rb）。
# 実行のたびに、ふりかえ帳のデータをすべて消して、作り直す。デモ用ではないユーザーがいる DB・本番環境では、何も作らずに止まる。
#
# db:prepare・db:setup・db:reset も、新しい DB を作るときに、このファイルを読み込む（CI のテスト用 DB、本番のデプロイ、bin/setup）。
# そのとき、デモデータを作ってしまわないよう、「bin/rails db:seed を直接実行したとき」だけ作る。
explicit_seed = defined?(Rake) && Rake.application.top_level_tasks.any? { |task| task.start_with?("db:seed") }
return unless explicit_seed

begin
  result = DemoData.load
rescue DemoData::Refused => e
  abort "デモデータを作りませんでした：#{e.message}"
end

puts "デモデータを作りました（すべて架空のデータです）。"
puts "  先生　：#{result[:teacher]}"
puts "  保護者：#{result[:guardians].join('、')}"
puts "  パスワード（共通）：#{result[:password]}"
puts "  生徒 #{result[:students]}人、固定枠 #{result[:lesson_slots]}、振替枠 #{result[:makeup_slots]}、欠席 #{result[:absences]}、振替権 #{result[:credits]}、振替予約 #{result[:reservations]}"
