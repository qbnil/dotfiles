#!/usr/bin/env bash
set -euo pipefail

# Directories to clean if empty
dirs=(
  "$HOME/.claude/backups"
  "$HOME/.claude/cache"
  "$HOME/.claude/commands"
  "$HOME/.claude/downloads"
  "$HOME/.claude/jobs"
  "$HOME/.claude/paste-cache"
  "$HOME/.claude/shell-snapshots"
  "$HOME/.claude/sessions"
)

for d in "${dirs[@]}"; do
  if [[ -d "$d" && -z "$(ls -A "$d" 2>/dev/null)" ]]; then
    echo "Removing empty directory: $d"
    rm -rf "$d"
  fi
done

# Delete credential file if present
if [[ -f "$HOME/.claude/.credentials.json" ]]; then
  echo "Removing credential file: .credentials.json"
  rm -f "$HOME/.claude/.credentials.json"
fi

# Rotate daemon.log: keep last 5 MB
LOG="$HOME/.claude/daemon.log"
if [[ -f "$LOG" ]]; then
  echo "Rotating daemon.log (keeping last 5 MB)"
  tail -c 5M "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
fi

# Prune file-history (remove the log file)
if [[ -f "$HOME/.claude/history.jsonl" ]]; then
  echo "Removing history.jsonl"
  rm -f "$HOME/.claude/history.jsonl"
fi

# Clear telemetry directory if empty
if [[ -d "$HOME/.claude/telemetry" && -z "$(ls -A "$HOME/.claude/telemetry")" ]]; then
  echo "Removing empty telemetry directory"
  rm -rf "$HOME/.claude/telemetry"
fi

echo "Cleanup completed."