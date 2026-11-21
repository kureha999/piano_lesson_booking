require "io/console"

namespace :teacher do
  desc "先生のアカウントを作る（NAME=名前 EMAIL=メールアドレス [PASSWORD=パスワード]）"
  task create: :environment do
    name = ENV["NAME"].to_s
    email = ENV["EMAIL"].to_s
    password = ENV["PASSWORD"]

    # PASSWORD を渡さなければ、入力を表示しないで聞く（シェルの履歴にパスワードを残さないため）
    if password.nil? && $stdin.tty?
      password = $stdin.getpass("パスワード: ")
    end

    result = CreateTeacher.call(name: name, email: email, password: password.to_s)
    abort "先生を作れませんでした：#{result.errors.join('、')}" unless result.success?

    puts "先生のアカウントを作りました：#{result.user.name}（#{result.user.email}）"
  end
end
