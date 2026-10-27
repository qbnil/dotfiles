#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
HELPERS_DIR="$CURRENT_DIR/helpers"

source "$HELPERS_DIR/plugin_functions.sh"

plugin_dir_exists() {
	[ -d "$1" ]
}

# Sources all *.tmux files from the plugin directory.
# Dotfiles deployments commonly store these scripts without executable bits,
# so execute them via bash instead of relying on mode 100755.
# No errors if the plugin dir does not exist.
silently_source_all_tmux_files() {
	local plugin_path="$1"
	local plugin_tmux_files="$plugin_path*.tmux"
	if plugin_dir_exists "$plugin_path"; then
		for tmux_file in $plugin_tmux_files; do
			# if the glob didn't find any files this will be the
			# unexpanded glob which obviously doesn't exist
			[ -f "$tmux_file" ] || continue
			bash "$tmux_file" >/dev/null 2>&1
		done
	fi
}

source_plugins() {
	local plugin plugin_path
	local plugins="$(tpm_plugins_list_helper)"
	for plugin in $plugins; do
		IFS='#' read -ra plugin <<< "$plugin"
		plugin_path="$(plugin_path_helper "${plugin[0]}")"
		silently_source_all_tmux_files "$plugin_path"
	done
}

main() {
	source_plugins
}
main
