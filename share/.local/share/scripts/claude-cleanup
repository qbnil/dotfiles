#!/usr/bin/env bash
set -euo pipefail

# Directories to clean if empty
dirs=(
  "/home/kent/.claude/backups"
  "/home/kent/.claude/cache"
  "/home/kent/.claude/commands"
  "/home/kent/.claude/downloads"
  "/home/kent/.claude/jobs"
  "/home/kent/.claude/paste-cache"
  "/home/kent/.claude/shell-snapshots"
  "/home/kent/.claude/sessions"
)

for d in "${dirs[@]}"; do
  if [[ -d "$d" && -z "$(ls -A "$d" 2>/dev/null)" ]]; then
    echo "Removing empty directory: $d"
    rm -rf "$d"
  fi
done

# Delete credential file if present
if [[ -f "/home/kent/.claude/.credentials.json" ]]; then
  echo "Removing credential file: .credentials.json"
  rm -f "/home/kent/.claude/.credentials.json"
fi

# Rotate daemon.log: keep last 5 MB
LOG="/home/kent/.claude/daemon.log"
if [[ -f "$LOG" ]]; then
  echo "Rotating daemon.log (keeping last 5 MB)"
  tail -c 5M "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
fi

# Prune file-history (remove the log file)
if [[ -f "/home/kent/.claude/history.jsonl" ]]; then
  echo "Removing history.jsonl"
  rm -f "/home/kent/.claude/history.jsonl"
fi

# Clear telemetry directory if empty
if [[ -d "/home/kent/.claude/telemetry" && -z "$(ls -A "/home/kent/.claude/telemetry")" ]]; then
  echo "Removing empty telemetry directory"
  rm -rf "/home/kent/.claude/telemetry"
fi

echo "Cleanup completed."