---
name: issue
description: GitHub の issue を1件だけ、ブランチ作成からテスト・コミット・PR・マージ・Projects の更新まで進め、報告して止まる。ユーザーが /issue <番号> と入力したときだけ使う。
argument-hint: "[issue番号]"
disable-model-invocation: true
---

# issue #$0 を1件だけ進める

この手順は issue **#$0 の1件だけ**を対象にする。最後まで終わったら報告して止まり、次の issue には進まない。

途中で次のどれかに当たったら、作業を止めて、状況と選択肢をユーザーに日本語で報告し、指示を待つ。

- issue の内容があいまいで、仕様を決めないと進められない
- issue の範囲を超える変更が必要になった
- 有料のツール・サービスや、課金が発生する操作が必要になった
- 同じテスト・CI の失敗を3回直しても解決しない

## 1. 着手前の確認

1. `git status` で未コミットの変更がないことを確認する。変更があれば止めて報告する。
2. `git switch main` → `git pull` で main を最新にする。
3. `gh issue view $0` で issue を読む。閉じている issue なら止めて報告する。
4. 本文の「先に終わらせるissue」にある issue がすべて閉じているかを `gh issue view <番号> --json state` で確認する。開いているものがあれば止めて報告する。
5. 本文の「やること」「調べること」「完了条件」と、関連する README の章（画面ID・機能ID・12章の設計資料）を読む。

## 2. 着手

1. `script/project.sh status $0 "In Progress"` で Projects を更新する。
2. `git switch -c feature/<内容を表す英語の短い名前>` でブランチを作る（例：`feature/factory-bot`）。

## 3. 調べること

issue に「調べること」がある場合や、新しい gem・ツールを入れる場合は、実装の前に公式の情報（RubyGems、公式ドキュメント、CHANGELOG）で次を確認する。

- 最新のバージョンと、Ruby 3.4・Rails 8.1 への対応
- 無料で使えること（OSS のライセンス、または無料プランの上限）

結果は PR の「調べたこと」に書く。

## 4. 実装

1. issue の「やること」を、範囲を広げずに実装する。
2. 追加・変更したロジックには、同じ作業の中で RSpec のテストを書く（モデル・サービスは spec/models・spec/services など、画面は request spec）。
   gem やツールを導入・設定するだけの場合は、設定を確かめるためのテストは書かず、実際にコマンドを実行した結果を PR の「動作確認」に書く。
3. 必要なら README（設計資料・環境変数・ローカル環境の手順）を更新する。

## 5. テストと確認（コミットの前に必ず行う）

1. `bin/rspec` を実行し、失敗が0件になるまで直す。
2. `bin/rubocop -a` で自動修正し、`bin/rubocop` で違反が0件であることを確認する。
3. `bin/ci` を実行し、すべてのステップが成功することを確認する。
4. issue の「完了条件」を1つずつ確認する。

コミット時にはフック（.claude/hooks/pre-commit-check.sh）でも RSpec と RuboCop が実行される。フックでコミットが止まったら、原因を直してからコミットし直す。フックを回避する操作はしない。

## 6. コミットと push

1. `git add` で変更を加え、`git status` で意図しないファイル（ログ・一時ファイル・秘密情報）が入っていないことを確認する。
2. 接頭辞を付けてコミットする（`feat:`・`fix:`・`test:`・`refactor:`・`docs:`・`chore:`・`ci:`）。メッセージは日本語で、何をしたかが分かるように書く。
3. `git push -u origin <ブランチ名>` で push する。

## 7. PR

1. `gh pr create --base main --title "<コミットと同じ形式のタイトル>" --body-file -` で PR を作る。本文は .github/pull_request_template.md の見出しに沿って書き、先頭に `Closes #$0` を入れる。
   - 「変更内容」：変更したファイルと内容
   - 「調べたこと」：手順3の結果（ある場合）
   - 「動作確認」：実行したコマンドと結果（bin/rspec の examples 数と failures 数、bin/ci の結果）
2. `sleep 10` の後、`gh pr checks --watch` で CI の完了を待つ。
3. 失敗したら原因を直し、手順5からやり直して push する。

## 8. マージと Projects の更新

1. CI がすべて成功したら、`gh pr merge --merge --delete-branch` でマージする（ユーザーの承認が求められる）。
2. `git switch main` → `git pull` で main を最新にする。
3. `script/project.sh status $0 "Done"` で Projects を Done にする。
4. `gh issue view $0 --json state` で issue が閉じていることを確認する。

## 9. 報告して止まる

次の内容を日本語で短く報告し、**そこで止まる。次の issue には進まない。**

- 完了した issue（#$0 とタイトル）と PR の URL
- 実装した内容（3〜5行）
- テストの結果（bin/rspec の examples 数・failures 数、bin/ci の結果、カバレッジがあればその値）
- 調べたことと、決めたこと（ある場合）
- 気づいた課題や、別の issue にしたほうがよいこと（ある場合）
- 次の候補の issue（Projects の Todo のうち、先に終わらせるissueがすべて閉じている、番号が最も小さいもの）
