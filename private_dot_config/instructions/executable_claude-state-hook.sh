#!/bin/sh
hook_json=$(cat)
session_id=$(printf '%s' "$hook_json" | jq -r '.session_id // empty' 2>/dev/null)
event_name=$(printf '%s' "$hook_json" | jq -r '.hook_event_name // empty' 2>/dev/null)
[ -n "$session_id" ] || exit 0
state_dir="$HOME/.claude/session-status"
state_file="$state_dir/$session_id.json"
mkdir -p "$state_dir"

refresh_hammerspoon_edge_bar() {
  ( /opt/homebrew/bin/hs -c 'refreshClaudeEdgeBar()' </dev/null >/dev/null 2>&1 & )
}

case "$event_name" in
  UserPromptSubmit|PreToolUse|PostToolUse) session_status=working ;;
  Notification)
    notification_type=$(printf '%s' "$hook_json" | jq -r '.notification_type // empty')
    notification_message=$(printf '%s' "$hook_json" | jq -r '.message // empty')
    if [ "$notification_type" = "permission_prompt" ] || printf '%s' "$notification_message" | grep -qi 'permission'; then
      session_status=waiting
    else
      exit 0
    fi
    ;;
  Stop) session_status=done ;;
  SessionEnd) rm -f "$state_file"; refresh_hammerspoon_edge_bar; exit 0 ;;
  *) exit 0 ;;
esac

temporary_file=$(mktemp "$state_dir/.tmp.XXXXXX")
printf '%s' "$hook_json" | jq -c \
  --arg status "$session_status" \
  --arg pane "${TMUX_PANE:-}" \
  --argjson updated "$(date +%s)" \
  '{session_id, status: $status, pane: $pane, cwd, updated: $updated}' > "$temporary_file"
mv "$temporary_file" "$state_file"
refresh_hammerspoon_edge_bar
exit 0
