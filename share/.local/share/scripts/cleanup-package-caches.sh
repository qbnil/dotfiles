#!/usr/bin/env bash
# cleanup-package-caches.sh
# Clean up package manager caches to free up disk space
# Supports: npm, cargo, pnpm, yarn, bun, pip, pipx, uv, go, gem, composer, nuget

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
DRY_RUN=false
VERBOSE=false
FORCE=false
SPECIFIC_TOOLS=()

# Print usage
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [TOOLS...]

Clean up package manager caches to free disk space.

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be cleaned without actually cleaning
    -v, --verbose       Verbose output
    -f, --force         Skip confirmation prompts
    --list              List supported tools and their cache locations

TOOLS (optional, space-separated):
    npm cargo pnpm yarn bun pip pipx uv go gem composer nuget

    If no tools specified, all available tools will be cleaned.

EXAMPLES:
    $(basename "$0")                    # Clean all caches
    $(basename "$0") npm cargo          # Clean only npm and cargo
    $(basename "$0") --dry-run          # Preview what would be cleaned
    $(basename "$0") -f                 # Clean all without prompts
EOF
}

# Log functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo -e "${BLUE}[DEBUG]${NC} $*" || true; }

# Get directory size in human-readable format
get_size() {
    local path="$1"
    if [[ -d "$path" ]]; then
        du -sh "$path" 2>/dev/null | cut -f1 || echo "0B"
    else
        echo "0B"
    fi
}

# Get directory size in bytes
get_size_bytes() {
    local path="$1"
    if [[ -d "$path" ]]; then
        du -sb "$path" 2>/dev/null | cut -f1 || echo 0
    else
        echo 0
    fi
}

# Confirm action
confirm() {
    local msg="$1"
    if [[ "$FORCE" == true ]]; then
        return 0
    fi
    read -rp "$msg [y/N] " -n 1
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Clean a directory
clean_dir() {
    local path="$1"
    local name="$2"
    local size_before
    local size_after

    if [[ ! -d "$path" ]]; then
        log_verbose "$name: Directory does not exist: $path"
        return 0
    fi

    size_before=$(get_size_bytes "$path")
    local size_human=$(get_size "$path")

    if [[ $size_before -eq 0 ]]; then
        log_verbose "$name: Already empty ($size_human)"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would clean $name ($size_human): $path"
        return 0
    fi

    if ! confirm "Clean $name cache ($size_human)?"; then
        log_info "Skipped $name"
        return 0
    fi

    log_verbose "Cleaning $name: $path"

    # Try to use the tool's native clean command first, fallback to rm
    case "$name" in
        npm)
            npm cache clean --force 2>/dev/null || rm -rf "$path"/*
            ;;
        cargo)
            cargo clean 2>/dev/null || rm -rf "$path"/*
            ;;
        pnpm)
            pnpm store prune 2>/dev/null || rm -rf "$path"/*
            ;;
        yarn)
            yarn cache clean 2>/dev/null || rm -rf "$path"/*
            ;;
        bun)
            bun pm cache rm 2>/dev/null || rm -rf "$path"/*
            ;;
        pip|pipx|uv)
            rm -rf "$path"/*
            ;;
        go)
            go clean -cache -modcache 2>/dev/null || rm -rf "$path"/*
            ;;
        gem)
            gem cleanup 2>/dev/null || rm -rf "$path"/*
            ;;
        composer)
            composer clear-cache 2>/dev/null || rm -rf "$path"/*
            ;;
        nuget)
            nuget locals all -clear 2>/dev/null || rm -rf "$path"/*
            ;;
        *)
            rm -rf "$path"/*
            ;;
    esac

    size_after=$(get_size_bytes "$path")
    local freed=$((size_before - size_after))
    local freed_human=$(numfmt --to=iec-i --suffix=B $freed 2>/dev/null || echo "${freed}B")

    log_success "Cleaned $name: freed $freed_human"
}

# Check if command exists
has_cmd() {
    command -v "$1" &>/dev/null
}

# Get cache directory for each tool
get_npm_cache() {
    if has_cmd npm; then
        npm config get cache 2>/dev/null || echo "$HOME/.npm"
    else
        echo "$HOME/.npm"
    fi
}

get_cargo_cache() {
    echo "${CARGO_HOME:-$HOME/.cargo}/registry/cache"
}

get_pnpm_cache() {
    if has_cmd pnpm; then
        pnpm store path 2>/dev/null || echo "$HOME/.local/share/pnpm/store"
    else
        echo "$HOME/.local/share/pnpm/store"
    fi
}

get_yarn_cache() {
    if has_cmd yarn; then
        yarn cache dir 2>/dev/null || echo "$HOME/.cache/yarn"
    else
        echo "$HOME/.cache/yarn"
    fi
}

get_bun_cache() {
    if has_cmd bun; then
        bun pm cache dir 2>/dev/null || echo "$HOME/.bun/install/cache"
    else
        echo "$HOME/.bun/install/cache"
    fi
}

get_pip_cache() {
    echo "$HOME/.cache/pip"
}

get_pipx_cache() {
    echo "$HOME/.local/pipx/cache"
}

get_uv_cache() {
    echo "$HOME/.cache/uv"
}

get_go_cache() {
    if has_cmd go; then
        go env GOCACHE 2>/dev/null || echo "$HOME/.cache/go-build"
    else
        echo "$HOME/.cache/go-build"
    fi
}

get_go_mod_cache() {
    if has_cmd go; then
        go env GOMODCACHE 2>/dev/null || echo "$(go env GOPATH 2>/dev/null || echo "$HOME/go")/pkg/mod"
    else
        echo "$HOME/go/pkg/mod"
    fi
}

get_gem_cache() {
    if has_cmd gem; then
        gem env gemdir 2>/dev/null | xargs -I{} echo {}/cache || echo "$HOME/.gem/cache"
    else
        echo "$HOME/.gem/cache"
    fi
}

get_composer_cache() {
    if has_cmd composer; then
        composer config cache-dir 2>/dev/null || echo "$HOME/.cache/composer"
    else
        echo "$HOME/.cache/composer"
    fi
}

get_nuget_cache() {
    echo "$HOME/.nuget/packages"
}

# List all supported tools and their cache locations
list_tools() {
    echo "Supported tools and cache locations:"
    echo

    local tools=(
        "npm:$(get_npm_cache)"
        "cargo:$(get_cargo_cache)"
        "pnpm:$(get_pnpm_cache)"
        "yarn:$(get_yarn_cache)"
        "bun:$(get_bun_cache)"
        "pip:$(get_pip_cache)"
        "pipx:$(get_pipx_cache)"
        "uv:$(get_uv_cache)"
        "go:$(get_go_cache) (build cache)"
        "go-mod:$(get_go_mod_cache) (module cache)"
        "gem:$(get_gem_cache)"
        "composer:$(get_composer_cache)"
        "nuget:$(get_nuget_cache)"
    )

    for tool in "${tools[@]}"; do
        local name="${tool%%:*}"
        local path="${tool#*:}"
        local size=$(get_size "$path")
        local installed="✓"
        if ! has_cmd "$name" && [[ "$name" != "go-mod" ]]; then
            installed="✗"
        fi
        printf "  %-12s %s %s (%s)\n" "$name" "$installed" "$path" "$size"
    done
}

# Main cleaning function for each tool
clean_npm() {
    local cache_dir=$(get_npm_cache)
    clean_dir "$cache_dir" "npm"
}

clean_cargo() {
    local cache_dir=$(get_cargo_cache)
    clean_dir "$cache_dir" "cargo"

    # Also clean cargo target directories in projects (optional, not done by default)
    log_verbose "Note: cargo clean also removes target/ directories in projects. Run 'cargo clean' in projects manually if needed."
}

clean_pnpm() {
    local cache_dir=$(get_pnpm_cache)
    clean_dir "$cache_dir" "pnpm"
}

clean_yarn() {
    local cache_dir=$(get_yarn_cache)
    clean_dir "$cache_dir" "yarn"
}

clean_bun() {
    local cache_dir=$(get_bun_cache)
    clean_dir "$cache_dir" "bun"
}

clean_pip() {
    local cache_dir=$(get_pip_cache)
    clean_dir "$cache_dir" "pip"
}

clean_pipx() {
    local cache_dir=$(get_pipx_cache)
    clean_dir "$cache_dir" "pipx"
}

clean_uv() {
    local cache_dir=$(get_uv_cache)
    clean_dir "$cache_dir" "uv"
}

clean_go() {
    local cache_dir=$(get_go_cache)
    clean_dir "$cache_dir" "go"

    local mod_cache_dir=$(get_go_mod_cache)
    clean_dir "$mod_cache_dir" "go-mod"
}

clean_gem() {
    local cache_dir=$(get_gem_cache)
    clean_dir "$cache_dir" "gem"
}

clean_composer() {
    local cache_dir=$(get_composer_cache)
    clean_dir "$cache_dir" "composer"
}

clean_nuget() {
    local cache_dir=$(get_nuget_cache)
    clean_dir "$cache_dir" "nuget"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --list)
            list_tools
            exit 0
            ;;
        *)
            SPECIFIC_TOOLS+=("$1")
            shift
            ;;
    esac
done

# If specific tools provided, use those; otherwise use all
if [[ ${#SPECIFIC_TOOLS[@]} -eq 0 ]]; then
    TOOLS_TO_CLEAN=(npm cargo pnpm yarn bun pip pipx uv go gem composer nuget)
else
    TOOLS_TO_CLEAN=("${SPECIFIC_TOOLS[@]}")
fi

# Validate tools
valid_tools=("npm" "cargo" "pnpm" "yarn" "bun" "pip" "pipx" "uv" "go" "gem" "composer" "nuget")
for tool in "${TOOLS_TO_CLEAN[@]}"; do
    if [[ ! " ${valid_tools[*]} " =~ " ${tool} " ]]; then
        log_error "Unknown tool: $tool"
        log_info "Valid tools: ${valid_tools[*]}"
        exit 1
    fi
done

# Print header
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Package Manager Cache Cleanup                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

if [[ "$DRY_RUN" == true ]]; then
    log_warn "DRY RUN MODE - No changes will be made"
    echo
fi

# Run cleaners
for tool in "${TOOLS_TO_CLEAN[@]}"; do
    # Check if tool is installed (except for go-mod which is part of go)
    if [[ "$tool" != "go-mod" ]] && ! has_cmd "$tool"; then
        log_verbose "Skipping $tool (not installed)"
        continue
    fi

    case "$tool" in
        npm) clean_npm ;;
        cargo) clean_cargo ;;
        pnpm) clean_pnpm ;;
        yarn) clean_yarn ;;
        bun) clean_bun ;;
        pip) clean_pip ;;
        pipx) clean_pipx ;;
        uv) clean_uv ;;
        go) clean_go ;;
        gem) clean_gem ;;
        composer) clean_composer ;;
        nuget) clean_nuget ;;
    esac
done

echo
log_success "Cleanup complete!"

if [[ "$DRY_RUN" == true ]]; then
    log_info "Run without --dry-run to actually clean the caches"
fi