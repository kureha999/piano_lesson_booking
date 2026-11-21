# CLAUDE.md

ふりかえ帳（piano_lesson_booking）は、自宅で1人で運営するピアノ教室向けの振替レッスン管理アプリです。副業のポートフォリオとして、issue ベースで開発しています。ユーザーとのやり取りは日本語で行います。

## 必ず守るルール

1. **1回の指示で進める issue は1つだけ。** issue が完了したら（PR のマージと Projects の Done まで）、結果を報告して止まり、次の指示を待つ。ユーザーが「続けて〇件」「#13〜#15 を進めて」のように明示した場合だけ続ける。自分から次の issue に着手しない。
2. **issue は `/issue <番号>` スキル（.claude/skills/issue/SKILL.md）の手順で進める。** 1 issue ＝ 1 ブランチ ＝ 1 PR。着手時に Projects を In Progress、マージ後に Done にする（`script/project.sh`）。
3. **新しいコードを追加したら、コミットの前に必ずテストを書いて実行する。** `bin/rspec`（失敗0件）、`bin/rubocop`（違反0件）、`bin/ci`（すべて成功）を確認してからコミット・push する。テストが失敗したままコミット・push しない。テストを消したり `skip` にしたりして通さない。
   - テストを書く対象は、アプリのコード（モデル・サービス・コントローラー・画面・メール・ジョブ）。
   - gem やツールを導入・設定するだけの issue では、その設定を確かめるためのテスト（gem の内部の API を呼ぶものなど）は書かない。`bin/rspec` などを実際に実行した結果で動作を確かめ、PR の「動作確認」に書く。
4. **外部ツール・サービスは無料のものだけを使う。料金が発生する操作はしない。**
   - gem・npm パッケージは OSS のライセンスで無料のものだけ。追加する前に、ライセンスと無料であることを確認して PR に書く。
   - SaaS（Sentry など）は無料プランの範囲だけで使う。有料プランへの変更、クレジットカードの登録、試用期間の後に課金されるサービスの利用はしない。
   - AWS は無料プランのクレジットの範囲だけで使い、リソースを作る・変更する前にユーザーに確認する。
   - 料金が発生するかどうか判断できないときは、作業を止めてユーザーに確認する。

## 判断に迷ったとき

- 仕様があいまいなとき、issue の範囲外の変更が必要なときは、実装を止めて選択肢を示し、ユーザーに確認する。
- バージョン・サポート期限・料金などの変わりやすい情報は、推測せず公式の情報で調べてから使う。
- 同じエラーを3回直しても解決しないときは、止めて状況を報告する。

## 技術スタック

- Ruby 3.4.13（mise で管理）／ Rails 8.1 ／ PostgreSQL 17（Homebrew、パスワードなしで接続）
- Hotwire（Turbo・Stimulus、importmap）。React は使わない
- テスト：RSpec（rspec-rails 8.1）。Minitest は使わない（`rails new -T`）
- 認証：Devise（予定）、認可：Pundit（予定）
- CI：GitHub Actions（.github/workflows/ci.yml）、手元では `bin/ci`（config/ci.rb）
- インフラ（M7 で予定）：AWS（EC2・RDS・S3・CloudFront・SES）を Terraform で構築

## よく使うコマンド

```bash
bin/rspec                         # すべてのテスト
bin/rspec spec/models/user_spec.rb:12   # ファイル・行を指定
bin/rubocop -a                    # 自動修正
bin/rubocop                       # Lint
bin/ci                            # RuboCop・セキュリティ監査・Brakeman をまとめて実行
bin/rails db:prepare              # DB の作成とマイグレーション
bin/rails server                  # http://localhost:3000

script/project.sh status <番号> "In Progress"   # Projects の Status を変更（Todo / In Progress / Done）
script/project.sh show <番号>                   # Status と Story Points を確認
gh issue view <番号>                             # issue の内容を確認
```

## ブランチ・コミット・PR

- ブランチ名：`feature/<内容を表す英語の短い名前>`（例：`feature/factory-bot`）。main に直接コミット・push しない。
- コミットメッセージ：接頭辞＋日本語。接頭辞は `feat:`・`fix:`・`test:`・`refactor:`・`docs:`・`chore:`・`ci:`。
- PR：.github/pull_request_template.md に沿って書き、本文に `Closes #<番号>` を入れる。CI がすべて成功してからマージする（`gh pr merge --merge --delete-branch`）。
- `git push --force`、`git reset --hard`、`--no-verify` は使わない。

## コードの規則

- RuboCop は rubocop-rails-omakase に従う（文字列はダブルクォート、配列の括弧の内側に空白）。
- 画面の文言・バリデーションのメッセージ・コメントは日本語。
- 締切や月の区切りは日本時間で判定する（`config.time_zone = "Tokyo"`）。`time` 型の列はタイムゾーンを変換しない。
- 同時操作で破れてはいけないルール（二重予約・定員・先生は1人）は DB の制約で守り、それ以外はモデルで確認する。
- 複数のモデルをまたぐ処理は、Controller や Model に書き込まず、クラスに切り出す。
- テーブル・カラムは README 12-6 の ER 図に合わせる。変更が必要なら、先にユーザーに確認し、README も更新する。

## 設計資料（README.md）

作業の前に、該当する章を読む。

| 章 | 内容 |
|---|---|
| 8 | 機能一覧（機能ID F-01〜F-12） |
| 12-2 | 振替ルールの仕様（締切・月の上限・期限・定員） |
| 12-3 | ユーザーと生徒の関係（ログインは先生と保護者だけ、兄弟に対応） |
| 12-4 | 画面一覧（画面ID C・P・T・E） |
| 12-5 | 画面遷移図 |
| 12-6 | ER 図・制約・振替権の状態の判定 |
| 14 | 開発の進め方（ストーリーポイント、issue の分け方、完了の定義） |

## issue と Projects

- issue は #11〜#72。**MVP は #60 まで**（M1〜M6）。#61〜#72（M7 AWS公開）は MVP の後に行う。
- Projects：「ふりかえ帳 開発ボード」（https://github.com/users/kureha999/projects/22）。Status は Todo → In Progress → Done、ストーリーポイントは「Story Points」（1 SP ＝ 約2時間、1・2・3・5）。
- 新しい issue が必要になったら、作らずにユーザーに提案する。

## 注意点

- `.gitignore` の `/.env*` は `.env.example` も除外してしまう。#17（.env.exampleの作成）では `!/.env.example` を追加する。
- `.env`、`config/master.key` などの秘密情報は読まない・コミットしない。
- 画面の確認のためにブラウザが必要なときは、ユーザーに確認を依頼する。

## Compact Instructions

会話を要約するときは、次を必ず残す：作業中の issue 番号とブランチ名、終わった手順と残りの手順、未解決のエラー、ユーザーが決めたこと。「1 issue が終わったら止まる」ルールは要約後も守る。
