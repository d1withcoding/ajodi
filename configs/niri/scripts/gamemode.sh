#!/usr/bin/env bash
#
# Game mode visual strip for niri (Ajodi).
#
set -euo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
gm_file="$config_dir/gamemode.kdl"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/ajodi"
mkdir -p "$state_dir"

case "${1:-}" in
    on)
        echo "animations { off; }" > "$gm_file"
        touch "$state_dir/gamemode-active"
        ;;
    off)
        echo "// Gamemode disabled" > "$gm_file"
        rm -f "$state_dir/gamemode-active"
        ;;
    *)
        echo "usage: gamemode.sh on|off" >&2
        exit 1
        ;;
esac

