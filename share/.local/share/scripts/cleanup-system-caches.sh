#!/usr/bin/env bash
# cleanup-system-caches.sh
# Comprehensive system cache cleanup script
# Cleans: package managers, docker, systemd journals, trash, thumbnails, temporary files

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

DRY_RUN=false
VERBOSE=false
FORCE=false
INCLUDE_DOCKER=false
INCLUDE_JOURNALS=false
INCLUDE_TRASH=false
INCLUDE_THUMBNAILS=false
INCLUDE_TEMP=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Comprehensive system cache cleanup.

OPTIONS:
    -h, --help              Show this help
    -d, --dry-run           Show what would be cleaned
    -v, --verbose           Verbose output
    -f, --force             Skip confirmations
    --all                   Enable all cleanup categories
    --docker                Clean Docker (images, containers, volumes, build cache)
    --journals              Clean systemd journals (keep last 2 weeks)
    --trash                 Clean user trash directories
    --thumbnails            Clean thumbnail caches
    --temp                  Clean /tmp and /var/tmp (files older than 7 days)
    --packages              Clean package manager caches (uses cleanup-package-caches.sh)

EXAMPLES:
    $(basename "$0") --all --dry-run      # Preview full cleanup
    $(basename "$0") --docker --force     # Clean Docker without prompts
    $(basename "$0") --packages           # Clean package caches only
EOF
}

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo -e "${CYAN}[DEBUG]${NC} $*" || true; }

get_size() { du -sh "$1" 2>/dev/null | cut -f1 || echo "0B"; }
get_size_bytes() { du -sb "$1" 2>/dev/null | cut -f1 || echo 0; }

confirm() {
    [[ "$FORCE" == true ]] && return 0
    read -rp "$1 [y/N] " -n 1
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

clean_path() {
    local path="$1"
    local name="$2"
    local filter="${3:-}"

    [[ ! -d "$path" ]] && { log_verbose "$name: not found"; return 0; }

    local size_before=$(get_size_bytes "$path")
    local size_human=$(get_size "$path")

    [[ $size_before -eq 0 ]] && { log_verbose "$name: empty"; return 0; }

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would clean $name ($size_human): $path"
        return 0
    fi

    if ! confirm "Clean $name ($size_human)?"; then
        log_info "Skipped $name"
        return 0
    fi

    if [[ -n "$filter" ]]; then
        find "$path" -type f $filter -delete 2>/dev/null || true
        find "$path" -type d -empty -delete 2>/dev/null || true
    else
        rm -rf "$path"/* 2>/dev/null || true
        rm -rf "$path"/.* 2>/dev/null || true
    fi

    local size_after=$(get_size_bytes "$path")
    local freed=$((size_before - size_after))
    local freed_human=$(numfmt --to=iec-i --suffix=B $freed 2>/dev/null || echo "${freed}B")
    log_success "Cleaned $name: freed $freed_human"
}

# Docker cleanup
clean_docker() {
    if ! command -v docker &>/dev/null; then
        log_verbose "Docker not installed"
        return 0
    fi

    log_info "Checking Docker disk usage..."
    docker system df -v 2>/dev/null || true

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would run: docker system prune -a --volumes"
        return 0
    fi

    if confirm "Clean Docker (unused images, containers, volumes, build cache)?"; then
        docker system prune -a --volumes -f
        log_success "Docker cleanup complete"
    else
        log_info "Skipped Docker"
    fi
}

# Systemd journals
clean_journals() {
    if ! command -v journalctl &>/dev/null; then
        log_verbose "systemd not available"
        return 0
    fi

    local current_size=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMGT]?B' || echo "unknown")
    log_info "Current journal size: $current_size"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would run: journalctl --vacuum-time=2weeks"
        return 0
    fi

    if confirm "Clean systemd journals (keep last 2 weeks)?"; then
        journalctl --vacuum-time=2weeks
        log_success "Journal cleanup complete"
    else
        log_info "Skipped journals"
    fi
}

# Trash
clean_trash() {
    local trash_dirs=(
        "$HOME/.local/share/Trash"
        "$HOME/.Trash"
        "/root/.local/share/Trash"
    )

    for dir in "${trash_dirs[@]}"; do
        clean_path "$dir" "Trash ($(basename "$(dirname "$dir")"))"
    done
}

# Thumbnails
clean_thumbnails() {
    local thumb_dirs=(
        "$HOME/.cache/thumbnails"
        "$HOME/.thumbnails"
        "/var/cache/thumbnails"
    )

    for dir in "${thumb_dirs[@]}"; do
        clean_path "$dir" "Thumbnails"
    done
}

# Temporary files
clean_temp() {
    # /tmp - files older than 7 days
    if [[ -d /tmp ]]; then
        local count=$(find /tmp -type f -mtime +7 2>/dev/null | wc -l)
        if [[ $count -gt 0 ]]; then
            log_info "Found $count files in /tmp older than 7 days"
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY RUN] Would delete /tmp files older than 7 days"
            elif confirm "Delete /tmp files older than 7 days?"; then
                find /tmp -type f -mtime +7 -delete 2>/dev/null || true
                log_success "Cleaned /tmp"
            fi
        fi
    fi

    # /var/tmp - files older than 30 days
    if [[ -d /var/tmp ]]; then
        local count=$(find /var/tmp -type f -mtime +30 2>/dev/null | wc -l)
        if [[ $count -gt 0 ]]; then
            log_info "Found $count files in /var/tmp older than 30 days"
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY RUN] Would delete /var/tmp files older than 30 days"
            elif confirm "Delete /var/tmp files older than 30 days?"; then
                find /var/tmp -type f -mtime +30 -delete 2>/dev/null || true
                log_success "Cleaned /var/tmp"
            fi
        fi
    fi
}

# Package managers (calls the other script)
clean_packages() {
    if [[ -f /home/kent/i-projects/scripts/cleanup-package-caches.sh ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            /home/kent/i-projects/scripts/cleanup-package-caches.sh --dry-run
        else
            /home/kent/i-projects/scripts/cleanup-package-caches.sh ${FORCE:+-f} ${VERBOSE:+-v}
        fi
    else
        log_warn "Package cleanup script not found"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) usage; exit 0 ;;
        -d|--dry-run) DRY_RUN=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -f|--force) FORCE=true; shift ;;
        --all)
            INCLUDE_DOCKER=true
            INCLUDE_JOURNALS=true
            INCLUDE_TRASH=true
            INCLUDE_THUMBNAILS=true
            INCLUDE_TEMP=true
            shift ;;
        --docker) INCLUDE_DOCKER=true; shift ;;
        --journals) INCLUDE_JOURNALS=true; shift ;;
        --trash) INCLUDE_TRASH=true; shift ;;
        --thumbnails) INCLUDE_THUMBNAILS=true; shift ;;
        --temp) INCLUDE_TEMP=true; shift ;;
        --packages) clean_packages; exit 0 ;;
        *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# Default: if no specific flags, show help
if [[ "$INCLUDE_DOCKER" == false && "$INCLUDE_JOURNALS" == false && \
      "$INCLUDE_TRASH" == false && "$INCLUDE_THUMBNAILS" == false && \
      "$INCLUDE_TEMP" == false ]]; then
    usage
    exit 0
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              System Cache Cleanup                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

[[ "$DRY_RUN" == true ]] && { log_warn "DRY RUN MODE"; echo; }

[[ "$INCLUDE_DOCKER" == true ]] && clean_docker
[[ "$INCLUDE_JOURNALS" == true ]] && clean_journals
[[ "$INCLUDE_TRASH" == true ]] && clean_trash
[[ "$INCLUDE_THUMBNAILS" == true ]] && clean_thumbnails
[[ "$INCLUDE_TEMP" == true ]] && clean_temp

echo
log_success "System cleanup complete!"