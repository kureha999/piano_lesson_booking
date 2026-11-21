require "rails_helper"
require "rake"

RSpec.describe "teacher:create タスク", type: :task do
  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("teacher:create")
    Rake::Task["teacher:create"].reenable
  end

  around do |example|
    keys = %w[NAME EMAIL PASSWORD]
    saved = ENV.values_at(*keys)
    example.run
  ensure
    keys.zip(saved).each { |key, value| ENV[key] = value }
  end

  def run_task(**env)
    env.each { |key, value| ENV[key.to_s] = value }
    Rake::Task["teacher:create"].invoke
  end

  it "先生を作り、そのアカウントでログインできる" do
    expect { run_task(NAME: "山田先生", EMAIL: "teacher@example.com", PASSWORD: "password123") }
      .to output(/先生のアカウントを作りました：山田先生（teacher@example.com）/).to_stdout

    teacher = User.teacher.sole
    expect(teacher.email).to eq "teacher@example.com"
    expect(teacher.valid_password?("password123")).to be true
  end

  it "すでに先生がいる場合は、メッセージを出して終了する" do
    create(:teacher)

    expect { run_task(NAME: "山田先生", EMAIL: "teacher2@example.com", PASSWORD: "password123") }
      .to raise_error(SystemExit).and output(/先生を作れませんでした：.*すでに登録されています/).to_stderr
    expect(User.teacher.count).to eq 1
  end
end
