#!/usr/bin/env bash
# GitHub Projects「ふりかえ帳 開発ボード」の issue を操作する
#
# 使い方:
#   script/project.sh add    <issue番号>                    Projects に追加する（Status は Todo）
#   script/project.sh status <issue番号> <Todo|In Progress|Done>
#   script/project.sh points <issue番号> <1|2|3|5>           Story Points を設定する
#   script/project.sh show   <issue番号>                    Status と Story Points を表示する
#
# 必要なもの: gh（`gh auth refresh -s project` で project の権限を付けておく）
set -euo pipefail

OWNER="kureha999"
REPO="piano_lesson_booking"
PROJECT=22

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

[ $# -ge 2 ] || usage
ACTION="$1"
ISSUE="$2"

project_id() {
  gh project view "$PROJECT" --owner "$OWNER" --format json --jq '.id'
}

field_id() {
  gh project field-list "$PROJECT" --owner "$OWNER" --format json \
    --jq ".fields[] | select(.name == \"$1\") | .id"
}

item_id() {
  gh project item-list "$PROJECT" --owner "$OWNER" --limit 500 --format json \
    --jq ".items[] | select(.content.number == $ISSUE) | .id"
}

require_item() {
  local id
  id=$(item_id)
  if [ -z "$id" ]; then
    echo "✗ issue #$ISSUE が Projects にありません（script/project.sh add $ISSUE で追加できます）" >&2
    exit 1
  fi
  echo "$id"
}

case "$ACTION" in
  add)
    gh project item-add "$PROJECT" --owner "$OWNER" \
      --url "https://github.com/$OWNER/$REPO/issues/$ISSUE" > /dev/null
    sleep 3 # 追加が反映されるまで待つ
    "$0" status "$ISSUE" "Todo"
    ;;
  status)
    [ $# -eq 3 ] || usage
    STATUS="$3"
    OPTION_ID=$(gh project field-list "$PROJECT" --owner "$OWNER" --format json \
      --jq ".fields[] | select(.name == \"Status\") | .options[] | select(.name == \"$STATUS\") | .id")
    if [ -z "$OPTION_ID" ]; then
      echo "✗ Status「$STATUS」がありません（Todo / In Progress / Done のどれかを指定してください）" >&2
      exit 1
    fi
    ITEM_ID=$(require_item)
    gh project item-edit --id "$ITEM_ID" --project-id "$(project_id)" \
      --field-id "$(field_id Status)" --single-select-option-id "$OPTION_ID" > /dev/null
    echo "✓ #$ISSUE の Status を「$STATUS」にしました"
    ;;
  points)
    [ $# -eq 3 ] || usage
    POINTS="$3"
    case "$POINTS" in
      1|2|3|5) ;;
      *) echo "✗ Story Points は 1・2・3・5 のどれかにしてください（8以上はissueを分けます）" >&2; exit 1 ;;
    esac
    ITEM_ID=$(require_item)
    gh project item-edit --id "$ITEM_ID" --project-id "$(project_id)" \
      --field-id "$(field_id "Story Points")" --number "$POINTS" > /dev/null
    echo "✓ #$ISSUE の Story Points を $POINTS にしました"
    ;;
  show)
    gh project item-list "$PROJECT" --owner "$OWNER" --limit 500 --format json \
      --jq ".items[] | select(.content.number == $ISSUE) | \"#\(.content.number) \(.content.title)  Status: \(.status // \"-\")  Story Points: \(([to_entries[] | select(.key | test(\"^story\"; \"i\")) | .value][0]) // \"-\")\""
    ;;
  *)
    usage
    ;;
esac
