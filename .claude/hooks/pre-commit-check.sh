#!/bin/bash
# Claude Code が `git commit` を実行する直前に動くフック（.claude/settings.json で登録）
#   - main ブランチへの直接コミットを止める
#   - RSpec と RuboCop を実行し、失敗したらコミットを止める
# 終了コード 2 でコミットが止まり、標準エラー出力の内容が Claude に伝わります。

cat > /dev/null # フックに渡される JSON は使わないので読み捨てる

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
