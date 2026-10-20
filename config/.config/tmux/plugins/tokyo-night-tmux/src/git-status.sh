#!/usr/bin/env bash

# Check if enabled
if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  ENABLED=$(tmux show-option -gv @tokyo-night-tmux_show_git 2>/dev/null)
else
  ENABLED=${ENABLED:-1}
fi
[[ ${ENABLED} -ne 1 ]] && exit 0

# Ensure non-interactive SSH auth: never prompt, never hang, fail fast
export GIT_TERMINAL_PROMPT=0
export SSH_ASKPASS=/usr/bin/false
export SSH_ASKPASS_REQUIRE=never
export DISPLAY=""
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5"

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../lib/coreutils-compat.sh"
source "$CURRENT_DIR/themes.sh"

cd "$1" || exit 1
RESET="#[fg=${THEME[foreground]},bg=${THEME[background]},nobold,noitalics,nounderscore,nodim]"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
GIT_DIR="$(git rev-parse --absolute-git-dir 2>/dev/null)"

if [[ ${#BRANCH} -gt 25 ]]; then
  BRANCH="${BRANCH:0:25}…"
fi

STATUS_CHANGED=""
STATUS_INSERTIONS=""
STATUS_DELETIONS=""
STATUS_UNTRACKED=""

# --- Local dirty state (always computed, always shown as counts) ---
DIFF_COUNTS=($(git diff HEAD --numstat 2>/dev/null | awk 'NF==3 {changed+=1; ins+=$1; del+=$2} END {printf("%d %d %d", changed, ins, del)}'))
CHANGED_COUNT=${DIFF_COUNTS[0]:-0}
INSERTIONS_COUNT=${DIFF_COUNTS[1]:-0}
DELETIONS_COUNT=${DIFF_COUNTS[2]:-0}
UNTRACKED_COUNT="$(git ls-files --other --exclude-standard 2>/dev/null | wc -l | bc)"
DIRTY=0
[[ $CHANGED_COUNT -gt 0 || $INSERTIONS_COUNT -gt 0 || $DELETIONS_COUNT -gt 0 || $UNTRACKED_COUNT -gt 0 ]] && DIRTY=1

if [[ $CHANGED_COUNT -gt 0 ]]; then
  STATUS_CHANGED="${RESET}#[fg=${THEME[yellow]},bg=${THEME[background]},bold] ${CHANGED_COUNT} "
fi
if [[ $INSERTIONS_COUNT -gt 0 ]]; then
  STATUS_INSERTIONS="${RESET}#[fg=${THEME[green]},bg=${THEME[background]},bold] ${INSERTIONS_COUNT} "
fi
if [[ $DELETIONS_COUNT -gt 0 ]]; then
  STATUS_DELETIONS="${RESET}#[fg=${THEME[red]},bg=${THEME[background]},bold] ${DELETIONS_COUNT} "
fi
if [[ $UNTRACKED_COUNT -gt 0 ]]; then
  STATUS_UNTRACKED="${RESET}#[fg=${THEME[black]},bg=${THEME[background]},bold] ${UNTRACKED_COUNT} "
fi

# --- Remote sync state (throttled fetch so it works while dirty too) ---
BEHIND=0
AHEAD=0
if [[ -n "$BRANCH" ]] && git remote get-url origin >/dev/null 2>&1; then
  # Fetch at most every 5 minutes per repo
  NOW=$(date +%s)
  LAST_FETCH=0
  if [[ -f "$GIT_DIR/FETCH_HEAD" ]]; then
    LAST_FETCH=$(stat -c %Y "$GIT_DIR/FETCH_HEAD" 2>/dev/null || echo 0)
  fi
  if [[ $((NOW - LAST_FETCH)) -gt 300 ]]; then
    git fetch --quiet --no-tags origin "$BRANCH" 2>/dev/null || true
  fi

  if git show-ref --verify --quiet "refs/remotes/origin/${BRANCH}"; then
    BEHIND=$(git rev-list --count "HEAD..origin/${BRANCH}" 2>/dev/null)
    AHEAD=$(git rev-list --count "origin/${BRANCH}..HEAD" 2>/dev/null)
    BEHIND=${BEHIND:-0}
    AHEAD=${AHEAD:-0}
  fi
fi

# --- Status icon: remote sync wins over dirty (counts still show dirty) ---
if [[ $BEHIND -gt 0 && $AHEAD -gt 0 ]]; then
  REMOTE_STATUS="$RESET#[bg=${THEME[background]},fg=${THEME[yellow]},bold]▒ 󰆴 "
  SYNC_COUNTS="${RESET}#[fg=${THEME[magenta]},bg=${THEME[background]},bold]↓${BEHIND}${RESET}#[fg=${THEME[red]},bg=${THEME[background]},bold]↑${AHEAD} "
elif [[ $BEHIND -gt 0 ]]; then
  REMOTE_STATUS="$RESET#[bg=${THEME[background]},fg=${THEME[magenta]},bold]▒ 󰛀 "
  SYNC_COUNTS="${RESET}#[fg=${THEME[magenta]},bg=${THEME[background]},bold]↓${BEHIND} "
elif [[ $AHEAD -gt 0 ]]; then
  REMOTE_STATUS="$RESET#[bg=${THEME[background]},fg=${THEME[red]},bold]▒ 󰛃 "
  SYNC_COUNTS="${RESET}#[fg=${THEME[red]},bg=${THEME[background]},bold]↑${AHEAD} "
elif [[ $DIRTY -eq 1 ]]; then
  REMOTE_STATUS="$RESET#[bg=${THEME[background]},fg=${THEME[bred]},bold]▒ 󱓎"
  SYNC_COUNTS=""
else
  REMOTE_STATUS="$RESET#[bg=${THEME[background]},fg=${THEME[green]},bold]▒ "
  SYNC_COUNTS=""
fi

if [[ -n $BRANCH ]]; then
  echo "$REMOTE_STATUS $SYNC_COUNTS$RESET$BRANCH $STATUS_CHANGED$STATUS_INSERTIONS$STATUS_DELETIONS$STATUS_UNTRACKED"
fi
