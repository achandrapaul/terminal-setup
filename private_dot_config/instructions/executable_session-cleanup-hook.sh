#!/bin/sh
retention_days=7
for state_dir in "$HOME/.claude/tier" "$HOME/.claude/context" "$HOME/.claude/session-status"; do
  [ -d "$state_dir" ] && find "$state_dir" -type f -mtime +"$retention_days" -delete
done
exit 0
