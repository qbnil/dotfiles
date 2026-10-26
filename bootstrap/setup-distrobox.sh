#!/usr/bin/env bash
# Recreate the rootless Kali Distrobox used by this desktop profile.
set -Eeuo pipefail

name="${DISTROBOX_NAME:-kali}"
image="${DISTROBOX_IMAGE:-docker.io/kalilinux/kali-rolling:latest}"
containerfile="$(dirname "$0")/kali-distrobox/Containerfile"

command -v podman >/dev/null || { echo "podman is required" >&2; exit 1; }
command -v distrobox >/dev/null || { echo "distrobox is required" >&2; exit 1; }

if [ "${DISTROBOX_BUILD:-0}" = "1" ]; then
    image="${DISTROBOX_IMAGE:-localhost/kali-distrobox:minimal}"
    echo "Building $image..."
    podman build --build-arg USER_NAME="$(id -un)" --build-arg USER_UID="$(id -u)" \
        -t "$image" -f "$containerfile" "$(dirname "$containerfile")"
fi

if distrobox list --no-color 2>/dev/null | awk -F'|' -v n="$name" 'NR > 1 {gsub(/[[:space:]]/, "", $2); if ($2 == n) found=1} END {exit !found}'; then
    echo "Distrobox '$name' already exists."
    exit 0
fi

echo "Creating rootless Distrobox '$name' from $image..."
distrobox create --name "$name" --image "$image" --yes
echo "Created '$name'. Enter it with: distrobox enter $name"
