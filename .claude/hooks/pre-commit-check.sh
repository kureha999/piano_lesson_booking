#!/bin/bash
# Claude Code が Bash コマンドを実行する直前に動くフック（.claude/settings.json で登録）
# コマンドが `git commit` のときだけ、次を行う。ほかのコマンドは、何もせずに通す。
#   - main ブランチへの直接コミットを止める
#   - RSpec と RuboCop を実行し、失敗したらコミットを止める
# 終了コード 2 でコミットが止まり、標準エラー出力の内容が Claude に伝わります。
#
# 発火の判定：フックに渡される JSON の tool_input.command を読み、
# 「&&」「||」「;」「|」・改行で区切った各コマンドのうち、先頭が `git commit` のものがあるときだけ対象にする。
# （settings.json の `if` は、ループやヒアドキュメントを含むコマンドでは条件を判定できず、誤って発火するため）

input=$(cat)

# tool_input.command を取り出す。jq があれば jq、なければ sed と awk（\n・\"・\\ だけ元に戻す）
if command -v jq > /dev/null 2>&1; then
  command_text=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2> /dev/null)
else
  command_text=$(printf '%s' "$input" |
    sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' |
    awk '{ gsub(/\\n/, "\n"); gsub(/\\"/, "\""); gsub(/\\\\/, "\\"); print }')
fi

# コマンドを取り出せなかったときは、安全のため、これまでどおりチェックする
if [ -n "$command_text" ]; then
  is_commit=false
  while IFS= read -r segment; do
    segment=${segment#"${segment%%[![:space:]]*}"} # 先頭の空白を取る
    case "$segment" in
      "git commit" | "git commit "* | "git commit"$'\t'*) is_commit=true ;;
    esac
  done < <(printf '%s\n' "$command_text" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/;/\n/g' -e 's/|/\n/g')

  if [ "$is_commit" = false ]; then
    exit 0
  fi
fi

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" || exit 2

branch=$(git branch --show-current)
if [ "$branch" = "main" ]; then
  echo "main ブランチには直接コミットできません。feature/〇〇 のブランチを作ってからコミットしてください。" >&2
  exit 2
fi

log_file="tmp/pre-commit-check.log"
mkdir -p tmp

if [ -x bin/rspec ]; then
  if ! bin/rspec > "$log_file" 2>&1; then
    echo "RSpec が失敗したため、コミットを止めました。テストを修正してから、もう一度コミットしてください。" >&2
    echo "--- bin/rspec の出力（最後の40行） ---" >&2
    tail -n 40 "$log_file" >&2
    exit 2
  fi
fi

if ! bin/rubocop > "$log_file" 2>&1; then
  echo "RuboCop が失敗したため、コミットを止めました。bin/rubocop -a で自動修正できるものは修正し、残りは手で直してください。" >&2
  echo "--- bin/rubocop の出力（最後の40行） ---" >&2
  tail -n 40 "$log_file" >&2
  exit 2
fi

exit 0
