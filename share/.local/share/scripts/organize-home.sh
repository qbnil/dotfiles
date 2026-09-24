#!/usr/bin/env bash
# organize-home.sh
# Organize home directory according to XDG Base Directory Specification
# Moves dotfiles to appropriate locations: .config, .local/share, .cache

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
BACKUP_DIR="$HOME/.local/share/home-org-backup/$(date +%Y%m%d-%H%M%S)"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Organize home directory following XDG Base Directory Specification.

OPTIONS:
    -h, --help          Show this help
    -d, --dry-run       Show what would be moved without making changes
    -v, --verbose       Verbose output
    -f, --force         Skip confirmation prompts
    --backup-dir DIR    Custom backup directory (default: ~/.local/share/home-org-backup/TIMESTAMP)

WHAT THIS DOES:
    1. Moves config files from ~ to ~/.config/
    2. Moves data files from ~ to ~/.local/share/
    3. Moves cache files from ~ to ~/.cache/
    4. Creates symlinks for backwards compatibility where needed
    5. Sets up XDG environment variables in shell configs

FILES THAT WILL BE MOVED:
    Config (~/.config/):     .gitconfig, .bashrc, .bash_profile, .zshenv, .profile,
                             .xinitrc, .Xresources, .fehbg, .nvidia-settings-rc
    Data (~/.local/share/):  .ssh, .gnupg, .fonts, .icons, .themes,
                             Documents, Downloads, Pictures, Videos, Music
    Cache (~/.cache/):       Already in correct location

EXAMPLES:
    $(basename "$0") --dry-run      # Preview changes
    $(basename "$0") -f             # Organize without prompts
EOF
}

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo -e "${CYAN}[DEBUG]${NC} $*" || true; }

confirm() {
    [[ "$FORCE" == true || "$DRY_RUN" == true ]] && return 0
    read -rp "$1 [y/N] " -n 1
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Create backup
create_backup() {
    local src="$1"
    local name="$2"
    if [[ -e "$src" && ! -L "$src" ]]; then
        mkdir -p "$BACKUP_DIR"
        local dest="$BACKUP_DIR/$name"
        log_verbose "Backing up $src to $dest"
        if [[ "$DRY_RUN" == false ]]; then
            cp -r "$src" "$dest"
        fi
    fi
}

# Move file/dir with symlink
move_with_symlink() {
    local src="$1"
    local dest="$2"
    local name="$(basename "$src")"

    [[ ! -e "$src" ]] && { log_verbose "$name: not found"; return 0; }
    [[ -L "$src" ]] && { log_verbose "$name: already a symlink"; return 0; }
    [[ -e "$dest" && "$(readlink -f "$src")" == "$(readlink -f "$dest")" ]] && { log_verbose "$name: already in place"; return 0; }

    local size=$(du -sh "$src" 2>/dev/null | cut -f1)
    log_info "Moving $name ($size) -> $dest"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would move $src to $dest and create symlink"
        return 0
    fi

    if ! confirm "Move $name to $dest?"; then
        log_info "Skipped $name"
        return 0
    fi

    create_backup "$src" "$name"
    mkdir -p "$(dirname "$dest")"
    mv "$src" "$dest"
    ln -sf "$dest" "$src"
    log_success "Moved $name and created symlink"
}

# Move file/dir without symlink (for things that don't need backwards compat)
move_without_symlink() {
    local src="$1"
    local dest="$2"
    local name="$(basename "$src")"

    [[ ! -e "$src" ]] && { log_verbose "$name: not found"; return 0; }
    [[ -e "$dest" && "$(readlink -f "$src")" == "$(readlink -f "$dest")" ]] && { log_verbose "$name: already in place"; return 0; }

    local size=$(du -sh "$src" 2>/dev/null | cut -f1)
    log_info "Moving $name ($size) -> $dest"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would move $src to $dest"
        return 0
    fi

    if ! confirm "Move $name to $dest?"; then
        log_info "Skipped $name"
        return 0
    fi

    create_backup "$src" "$name"
    mkdir -p "$(dirname "$dest")"
    mv "$src" "$dest"
    log_success "Moved $name"
}

# Setup XDG dirs
setup_xdg_dirs() {
    log_info "Setting up XDG directories..."
    mkdir -p "$HOME/.config"
    mkdir -p "$HOME/.local/share"
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/.local/state"
    mkdir -p "$HOME/.cache"
    mkdir -p "$HOME/.config/shell"
    mkdir -p "$HOME/.config/bash"
    mkdir -p "$HOME/.config/git"
    mkdir -p "$HOME/.config/npm"
    mkdir -p "$HOME/.config/python"
    mkdir -p "$HOME/.config/x11"
    mkdir -p "$HOME/.config/ffmpeg"
    mkdir -p "$HOME/.config/java"
}

# Move config files to .config
move_config_files() {
    log_info "=== Moving config files to ~/.config/ ==="

    # Shell configs
    move_with_symlink "$HOME/.bashrc" "$HOME/.config/bash/bashrc"
    move_with_symlink "$HOME/.bash_profile" "$HOME/.config/bash/bash_profile"
    move_with_symlink "$HOME/.bash_logout" "$HOME/.config/bash/bash_logout"
    move_with_symlink "$HOME/.zshrc" "$HOME/.config/zsh/zshrc" 2>/dev/null || true
    move_with_symlink "$HOME/.zprofile" "$HOME/.config/zsh/zprofile" 2>/dev/null || true
    move_with_symlink "$HOME/.zshenv" "$HOME/.config/zsh/zshenv"
    move_with_symlink "$HOME/.profile" "$HOME/.config/shell/profile" 2>/dev/null || true

    # Git
    move_with_symlink "$HOME/.gitconfig" "$HOME/.config/git/config"
    move_with_symlink "$HOME/.gitignore_global" "$HOME/.config/git/ignore" 2>/dev/null || true

    # X11
    move_with_symlink "$HOME/.xinitrc" "$HOME/.config/x11/xinitrc"
    move_with_symlink "$HOME/.xprofile" "$HOME/.config/x11/xprofile" 2>/dev/null || true
    move_with_symlink "$HOME/.Xresources" "$HOME/.config/x11/Xresources" 2>/dev/null || true
    move_with_symlink "$HOME/.Xauthority" "$HOME/.config/x11/Xauthority" 2>/dev/null || true

    # Other configs
    move_with_symlink "$HOME/.fehbg" "$HOME/.config/feh/fehbg"
    move_with_symlink "$HOME/.nvidia-settings-rc" "$HOME/.config/nvidia/settings-rc"
    move_with_symlink "$HOME/.inputrc" "$HOME/.config/readline/inputrc" 2>/dev/null || true
    move_with_symlink "$HOME/.editrc" "$HOME/.config/editrc/editrc" 2>/dev/null || true

    # npm
    if [[ -f "$HOME/.npmrc" ]]; then
        move_with_symlink "$HOME/.npmrc" "$HOME/.config/npm/npmrc"
    fi

    # Python
    if [[ -f "$HOME/.pythonrc" ]]; then
        move_with_symlink "$HOME/.pythonrc" "$HOME/.config/python/pythonrc"
    fi
    if [[ -f "$HOME/.pypirc" ]]; then
        move_with_symlink "$HOME/.pypirc" "$HOME/.config/python/pypirc"
    fi

    # SSH - move to .config/ssh but keep symlink for compatibility
    move_with_symlink "$HOME/.ssh" "$HOME/.config/ssh"

    # GPG
    move_with_symlink "$HOME/.gnupg" "$HOME/.config/gnupg" 2>/dev/null || true

    # Fonts and themes
    move_without_symlink "$HOME/.fonts" "$HOME/.local/share/fonts"
    move_without_symlink "$HOME/.icons" "$HOME/.local/share/icons"
    move_without_symlink "$HOME/.themes" "$HOME/.local/share/themes" 2>/dev/null || true
}

# Move data directories to .local/share
move_data_dirs() {
    log_info "=== Moving data directories to ~/.local/share/ ==="

    # Standard XDG user dirs
    local xdg_dirs=(
        "Documents:documents"
        "Downloads:downloads"
        "Pictures:pictures"
        "Videos:videos"
        "Music:music"
        "Templates:templates"
        "Public:public"
    )

    for pair in "${xdg_dirs[@]}"; do
        local src_name="${pair%%:*}"
        local dest_name="${pair#*:}"
        local src="$HOME/$src_name"
        local dest="$HOME/.local/share/$dest_name"

        if [[ -d "$src" && ! -L "$src" ]]; then
            # Check if already a symlink to XDG location
            if [[ -L "$src" ]] && [[ "$(readlink "$src")" == "$dest" ]]; then
                log_verbose "$src_name: already linked to XDG location"
                continue
            fi

            move_without_symlink "$src" "$dest"

            # Create symlink for backwards compatibility
            if [[ "$DRY_RUN" == false ]]; then
                ln -sf "$dest" "$src"
                log_success "Created symlink $src -> $dest"
            else
                log_info "[DRY RUN] Would create symlink $src -> $dest"
            fi
        fi
    done

    # Other data
    move_without_symlink "$HOME/.local/share/cargo" "$HOME/.local/share/cargo" 2>/dev/null || true
    move_without_symlink "$HOME/.local/share/go" "$HOME/.local/share/go" 2>/dev/null || true
    move_without_symlink "$HOME/.local/share/npm" "$HOME/.local/share/npm" 2>/dev/null || true
}

# Clean up temp files in home
clean_home_temp() {
    log_info "=== Cleaning temporary files in home ==="

    local temp_files=(
        ".bash_history-*.tmp"
        ".bash_history-*~"
        "*~"
        ".#*"
        ".*.swp"
        ".*.swo"
    )

    for pattern in "${temp_files[@]}"; do
        if [[ "$DRY_RUN" == true ]]; then
            find "$HOME" -maxdepth 1 -name "$pattern" 2>/dev/null | while read -r f; do
                log_info "[DRY RUN] Would remove: $f"
            done
        else
            find "$HOME" -maxdepth 1 -name "$pattern" -delete 2>/dev/null && \
                log_success "Cleaned $pattern" || true
        fi
    done

    # Remove empty directories in home (except standard ones)
    local keep_dirs=("Documents" "Downloads" "Pictures" "Videos" "Music" "Templates" "Public" "Desktop" "i-projects" ".config" ".local" ".cache" ".ssh" ".claude")
    find "$HOME" -maxdepth 1 -type d -empty 2>/dev/null | while read -r dir; do
        local name="$(basename "$dir")"
        if [[ ! " ${keep_dirs[*]} " =~ " ${name} " ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY RUN] Would remove empty dir: $dir"
            else
                rmdir "$dir" && log_success "Removed empty directory: $name"
            fi
        fi
    done
}

# Setup shell configuration for XDG
setup_shell_xdg() {
    log_info "=== Setting up XDG environment in shell configs ==="

    local xdg_config='
# XDG Base Directory Specification
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

# Application-specific XDG overrides
export CARGO_HOME="$XDG_DATA_HOME/cargo"
export GOPATH="$XDG_DATA_HOME/go"
export GOBIN="$GOPATH/bin"
export GOMODCACHE="$XDG_CACHE_HOME/go/mod"
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME/npm/npmrc"
export NPM_CONFIG_CACHE="$XDG_CACHE_HOME/npm"
export PYTHONSTARTUP="$XDG_CONFIG_HOME/python/pythonrc"
export PYTHON_HISTORY="$XDG_DATA_HOME/python/history"
export _JAVA_OPTIONS="-Djava.util.prefs.userRoot=$XDG_CONFIG_HOME/java"
export DOCKER_CONFIG="$XDG_CONFIG_HOME/docker"
export KUBECONFIG="$XDG_CONFIG_HOME/kube/config"
export GNUPGHOME="$XDG_CONFIG_HOME/gnupg"
export PASSWORD_STORE_DIR="$XDG_DATA_HOME/password-store"
export WGETRC="$XDG_CONFIG_HOME/wget/wgetrc"
export INPUTRC="$XDG_CONFIG_HOME/readline/inputrc"
export LESSHISTFILE="$XDG_CACHE_HOME/less_history"
export NODE_REPL_HISTORY="$XDG_DATA_HOME/node_repl_history"
export SQLITE_HISTORY="$XDG_DATA_HOME/sqlite_history"
export TERMINFO="$XDG_DATA_HOME/terminfo"
export TERMINFO_DIRS="$XDG_DATA_HOME/terminfo:/usr/share/terminfo"
export XINITRC="$XDG_CONFIG_HOME/x11/xinitrc"
export XPROFILE="$XDG_CONFIG_HOME/x11/xprofile"
export XRESOURCES="$XDG_CONFIG_HOME/x11/Xresources"
export FFMPEG_DATADIR="$XDG_CONFIG_HOME/ffmpeg"
'

    # Create shell config file
    local shell_config="$HOME/.config/shell/xdg-env.sh"
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create $shell_config with XDG exports"
    else
        cat > "$shell_config" <<< "$xdg_config"
        log_success "Created $shell_config"
    fi

    # Create bash profile snippet
    local bash_profile_snippet="$HOME/.config/bash/xdg-env.sh"
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create $bash_profile_snippet"
    else
        cat > "$bash_profile_snippet" <<< "$xdg_config"
        log_success "Created $bash_profile_snippet"
    fi

    # Create zsh profile snippet
    local zsh_profile_snippet="$HOME/.config/zsh/xdg-env.zsh"
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create $zsh_profile_snippet"
    else
        cat > "$zsh_profile_snippet" <<< "$xdg_config"
        log_success "Created $zsh_profile_snippet"
    fi
}

# Update shell rc files to source XDG config
update_shell_rcs() {
    log_info "=== Updating shell RC files ==="

    # Bash
    local bashrc="$HOME/.config/bash/bashrc"
    local source_line='[ -f "$XDG_CONFIG_HOME/shell/xdg-env.sh" ] && source "$XDG_CONFIG_HOME/shell/xdg-env.sh"'

    if [[ "$DRY_RUN" == false ]]; then
        if [[ -f "$bashrc" ]]; then
            if ! grep -q "xdg-env.sh" "$bashrc"; then
                echo "" >> "$bashrc"
                echo "# Source XDG environment" >> "$bashrc"
                echo "$source_line" >> "$bashrc"
                log_success "Updated $bashrc"
            fi
        fi
    else
        log_info "[DRY RUN] Would add XDG source to $bashrc"
    fi

    # Zsh
    local zshrc="$HOME/.config/zsh/.zshrc"
    local zsh_source='[ -f "$XDG_CONFIG_HOME/shell/xdg-env.sh" ] && source "$XDG_CONFIG_HOME/shell/xdg-env.sh"'

    if [[ "$DRY_RUN" == false ]]; then
        if [[ -f "$zshrc" ]]; then
            if ! grep -q "xdg-env" "$zshrc"; then
                echo "" >> "$zshrc"
                echo "# Source XDG environment" >> "$zshrc"
                echo "$zsh_source" >> "$zshrc"
                log_success "Updated $zshrc"
            fi
        fi
    else
        log_info "[DRY RUN] Would add XDG source to $zshrc"
    fi
}

# Create user-dirs.dirs for XDG user directories
create_user_dirs() {
    log_info "=== Creating user-dirs.dirs ==="

    local user_dirs="$HOME/.config/user-dirs.dirs"
    local content='# This file is written by xdg-user-dirs-update
# If you want to change or add directories, just edit the line you are
# interested in. All local changes will be retained on the next run.
# Format is XDG_xxx_DIR="$HOME/xxx", where xxx is the directory name.
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/.local/share/downloads"
XDG_TEMPLATES_DIR="$HOME/.local/share/templates"
XDG_PUBLICSHARE_DIR="$HOME/.local/share/public"
XDG_DOCUMENTS_DIR="$HOME/.local/share/documents"
XDG_MUSIC_DIR="$HOME/.local/share/music"
XDG_PICTURES_DIR="$HOME/.local/share/pictures"
XDG_VIDEOS_DIR="$HOME/.local/share/videos"
'

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create $user_dirs"
    else
        cat > "$user_dirs" <<< "$content"
        log_success "Created $user_dirs"
    fi
}

# Organize i-projects
organize_projects() {
    log_info "=== Organizing i-projects ==="

    local projects_dir="$HOME/i-projects"
    [[ ! -d "$projects_dir" ]] && { log_verbose "i-projects not found"; return 0; }

    # Move large files to archive
    local large_files=(
        "DaVinci_Resolve_Studio_21.0.4_Linux.zip"
        "Windows 11 22H2 (x64) 24in1 +- Office 2021 by Eagle123 (10.2023).iso"
    )

    for file in "${large_files[@]}"; do
        local src="$projects_dir/$file"
        if [[ -f "$src" ]]; then
            local size=$(du -sh "$src" | cut -f1)
            log_warn "Found large file: $file ($size)"
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY RUN] Would move to archive"
            elif confirm "Move $file to ~/.local/share/archives?"; then
                mkdir -p "$HOME/.local/share/archives"
                mv "$src" "$HOME/.local/share/archives/"
                log_success "Moved $file to archives"
            fi
        fi
    done
}

# Print summary
print_summary() {
    echo
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              Home Organization Summary                       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo
    echo "XDG Directories:"
    echo "  Config:  ~/.config/          (application configs)"
    echo "  Data:    ~/.local/share/     (user data, fonts, icons, projects)"
    echo "  Cache:   ~/.cache/           (temporary cache files)"
    echo "  State:   ~/.local/state/     (application state)"
    echo "  Bin:     ~/.local/bin/       (user executables)"
    echo
    echo "Backup location: $BACKUP_DIR"
    echo
    echo "Next steps:"
    echo "  1. Restart your shell or run: source ~/.config/shell/xdg-env.sh"
    echo "  2. Run 'xdg-user-dirs-update' to update user directories"
    echo "  3. Check that applications still work correctly"
    echo "  4. Remove backup after verifying: rm -rf $BACKUP_DIR"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) usage; exit 0 ;;
        -d|--dry-run) DRY_RUN=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -f|--force) FORCE=true; shift ;;
        --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
        *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Home Directory Organizer                        ║"
echo "║         Following XDG Base Directory Specification           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

[[ "$DRY_RUN" == true ]] && { log_warn "DRY RUN MODE - No changes will be made"; echo; }

if ! confirm "This will reorganize your home directory. Continue?"; then
    log_info "Aborted"
    exit 0
fi

setup_xdg_dirs
move_config_files
move_data_dirs
clean_home_temp
setup_shell_xdg
update_shell_rcs
create_user_dirs
organize_projects

print_summary

if [[ "$DRY_RUN" == true ]]; then
    echo
    log_warn "DRY RUN COMPLETE - Run without --dry-run to apply changes"
fi