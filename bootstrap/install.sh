#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"

command -v stow >/dev/null || { printf '%s\n' 'GNU Stow is required (pacman -S stow).' >&2; exit 1; }

for dir in "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share" "$HOME/.local/state" "$HOME/.cache"; do
    mkdir -p "$dir"
done

printf '%s\n' 'Dry-run stow plan:'
stow --target="$HOME" --no-folding --simulate config bin share
printf '%s\n' 'If the plan is correct, run:'
printf '  stow --target="$HOME" --no-folding config bin share\n'
