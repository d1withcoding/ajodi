#!/usr/bin/env bash
set -euo pipefail

flags_file="${XDG_STATE_HOME:-$HOME/.local/state}/ajodi/flags.json"
WPDIR=$(jq -r '.wallpaperDir // ""' "$flags_file" 2>/dev/null || echo "")
if [ -z "$WPDIR" ]; then
    for cand in "$HOME/Pictures/Wallpapers" "$HOME/Pictures/wallpapers" "$HOME/Wallpapers" "$HOME/wallpapers"; do
        [ -d "$cand" ] || continue
        n=$(find "$cand" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' \) | head -2 | wc -l)
        if [ "$n" -ge 2 ]; then WPDIR="$cand"; break; fi
    done
    [ -n "$WPDIR" ] || WPDIR="$HOME/Ajodi/wallpapers"
fi
RESOLVED="${XDG_STATE_HOME:-$HOME/.local/state}/ajodi-wallpaper-dir"
printf '%s\n' "$WPDIR" > "$RESOLVED"
[ "${1:-}" = "resolve" ] && exit 0
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/ajodi-wallpaper"
MAP="${XDG_STATE_HOME:-$HOME/.local/state}/ajodi-wallpaper-map"
BAG="${XDG_STATE_HOME:-$HOME/.local/state}/ajodi-wallpaper-bag"
STILL="${XDG_STATE_HOME:-$HOME/.local/state}/ajodi-wallpaper-still.png"
WLOG="${XDG_STATE_HOME:-$HOME/.local/state}/ajodi/wallcolors.log"

is_video() {
    case "${1##*.}" in
        [Mm][Pp]4|[Ww][Ee][Bb][Mm]|[Mm][Kk][Vv]|[Mm][Oo][Vv]) return 0 ;;
        *) return 1 ;;
    esac
}

ensure_daemon() {
    awww query >/dev/null 2>&1 && return 0
    local attempt i
    for attempt in 1 2 3 4 5; do
        awww-daemon >/dev/null 2>&1 &
        for i in $(seq 1 15); do
            awww query >/dev/null 2>&1 && return 0
            sleep 0.2
        done
    done
    return 1
}

list_pics() {
    find "$WPDIR" -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' \)
}

refill_bag() {
    local current="" shuffled
    [ -r "$STATE" ] && current=$(cat "$STATE")
    shuffled=$(list_pics | shuf)
    [ -n "$shuffled" ] || return 0
    if [ "$(printf '%s\n' "$shuffled" | head -n1)" = "$current" ] && [ "$(printf '%s\n' "$shuffled" | wc -l)" -gt 1 ]; then
        shuffled=$(printf '%s\n' "$shuffled" | tail -n +2; printf '%s\n' "$current")
    fi
    mkdir -p "$(dirname "$BAG")"
    printf '%s\n' "$shuffled" > "$BAG"
}

pop_bag() {
    local line refilled=false
    mkdir -p "$(dirname "$BAG")"
    (
        flock 9
        while :; do
            if [ ! -s "$BAG" ]; then
                [ "$refilled" = true ] && exit 1
                refill_bag
                refilled=true
                [ -s "$BAG" ] || exit 1
            fi
            line=$(head -n1 "$BAG")
            tail -n +2 "$BAG" > "$BAG.tmp" && mv "$BAG.tmp" "$BAG"
            if [ -f "$line" ]; then
                printf '%s\n' "$line"
                exit 0
            fi
        done
    ) 9>"$BAG.lock"
}

outputs() {
    niri msg -j outputs 2>/dev/null | jq -r 'if type=="object" then keys[] else .[].name end'
}

focused_output() {
    niri msg -j focused-output 2>/dev/null | jq -r '.name // empty'
}

cursor_output() {
    focused_output
}

map_get() {
    awk -F'\t' -v o="$1" '$1 == o { print $2; exit }' "$MAP" 2>/dev/null || true
}

map_put() {
    mkdir -p "$(dirname "$MAP")"
    { awk -F'\t' -v o="$1" '$1 != o' "$MAP" 2>/dev/null || true; printf '%s\t%s\n' "$1" "$2"; } > "$MAP.tmp"
    mv "$MAP.tmp" "$MAP"
}

map_put_all() {
    local o
    mkdir -p "$(dirname "$MAP")"
    : > "$MAP.tmp"
    for o in $(outputs); do
        printf '%s\t%s\n' "$o" "$1" >> "$MAP.tmp"
    done
    mv "$MAP.tmp" "$MAP"
}

make_still() {
    ffmpeg -y -loglevel error -i "$1" -frames:v 1 -f image2 -c:v png "$2.tmp" && mv "$2.tmp" "$2"
}

apply_visual() {
    local pic="$1" out="${2:-}" show="$1" st
    mkdir -p "$(dirname "$STILL")"
    if is_video "$pic"; then
        st="${pic%.*}.thumb.png"
        if [ ! -f "$st" ]; then
            make_still "$pic" "$STILL"
            st="$STILL"
        fi
        show="$st"
    fi
    local oflag=()
    [ -n "$out" ] && oflag=(-o "$out")
    local cur_pmode cur_md cur_ms cur_mh
    cur_pmode=$(jq -r '.paletteMode // "static"' "$flags_file" 2>/dev/null || echo static)
    cur_md=$(jq -r 'if .manualDark == false then "light" else "dark" end' "$flags_file" 2>/dev/null || echo dark)
    cur_ms=$(jq -r '.manualSat // 0.5' "$flags_file" 2>/dev/null || echo 0.5)
    cur_mh=$(jq -r '.manualHue // 30' "$flags_file" 2>/dev/null || echo 30)

    mkdir -p "$(dirname "$WLOG")"
    if [ "$cur_pmode" = "manual" ]; then
        python3 "$(dirname "$0")/wallcolors.py" --hue "$cur_mh" "$cur_md" "$cur_ms" >>"$WLOG" 2>&1 || true
    else
        python3 "$(dirname "$0")/wallcolors.py" "$show" >>"$WLOG" 2>&1 || true
    fi

    # Read pre-computed wave anchor
    local pos_file="${XDG_STATE_HOME:-$HOME/.local/state}/ajodi-wave-pos"
    local wave_args=(--transition-type wave --transition-angle 30 --transition-step 90)
    if [ -s "$pos_file" ]; then
        local pos
        pos=$(cat "$pos_file" 2>/dev/null || true)
        if [ -n "$pos" ]; then
            wave_args+=(--transition-pos "$pos")
        fi
    fi

    awww img ${oflag[@]+"${oflag[@]}"} "$show" "${wave_args[@]}"
    if [ "$show" != "$pic" ]; then
       awww img ${oflag[@]+"${oflag[@]}"} "$pic" --transition-type none
    fi
}

sync_videos() {
    local desired="" actual="" o pic outs n_out n_vid
    outs=$(outputs)
    for o in $outs; do
        pic=$(map_get "$o")
        [ -n "$pic" ] && [ -f "$pic" ] && is_video "$pic" || continue
        desired+="$o"$'\t'"$pic"$'\n'
    done
    n_out=$(printf '%s\n' "$outs" | sed '/^$/d' | wc -l)
    n_vid=$(printf '%s' "$desired" | sed '/^$/d' | wc -l)
    if [ "$n_vid" -gt 0 ] && [ "$n_vid" = "$n_out" ] && [ "$(printf '%s' "$desired" | cut -f2 | sort -u | wc -l)" = 1 ]; then
        desired="*"$'\t'"$(printf '%s' "$desired" | head -n1 | cut -f2)"$'\n'
    fi
    desired=$(printf '%s' "$desired" | sort)
    actual=$(for pid in $(pgrep -x mpvpaper 2>/dev/null); do
        mapfile -d '' -t a 2>/dev/null < "/proc/$pid/cmdline" && [ "${#a[@]}" -ge 2 ] && printf '%s\t%s\n' "${a[-2]}" "${a[-1]}"
    done | sort || true)
    [ "$desired" = "$actual" ] && return 0
    if pgrep -x mpvpaper >/dev/null 2>&1; then
        pkill -x mpvpaper 2>/dev/null || true
        for _ in $(seq 1 10); do
            pgrep -x mpvpaper >/dev/null 2>&1 || break
            sleep 0.1
        done
    fi
    [ -n "$desired" ] || return 0
    sleep 0.8
    while IFS=$'\t' read -r o pic; do
        [ -n "$o" ] || continue
        setsid -f mpvpaper -p -o "no-audio loop-file=inf hwdec=auto panscan=1.0" "$o" "$pic" >/dev/null 2>&1
    done <<< "$desired"
}

palette_update() {
    local pmode focused pic show mh md
    focused=$(focused_output)
    pic=""
    [ -n "$focused" ] && pic=$(map_get "$focused")
    [ -n "$pic" ] || pic=$(cat "$STATE" 2>/dev/null || true)
    [ -n "$pic" ] && [ -f "$pic" ] || return 0
    show="$pic"
    if is_video "$pic"; then
        make_still "$pic" "$STILL" && show="$STILL" || return 0
    fi
    mkdir -p "$(dirname "$STATE")"
    printf '%s\n' "$pic" > "$STATE"
    pmode=$(jq -r '.paletteMode // "static"' "$flags_file" 2>/dev/null || echo static)
    mkdir -p "$(dirname "$WLOG")"
    if [ "$pmode" = "manual" ]; then
        mh=$(jq -r '.manualHue // 30' "$flags_file" 2>/dev/null || echo 30)
        md=$(jq -r 'if .manualDark == false then "light" else "dark" end' "$flags_file" 2>/dev/null || echo dark)
        ms=$(jq -r '.manualSat // 0.5' "$flags_file" 2>/dev/null || echo 0.5)
        python3 "$(dirname "$0")/wallcolors.py" --hue "$mh" "$md" "$ms" >>"$WLOG" 2>&1 || true
    else
        python3 "$(dirname "$0")/wallcolors.py" "$show" >>"$WLOG" 2>&1 || true
    fi
    busctl --user call com.mitchellh.ghostty /com/mitchellh/ghostty org.gtk.Actions \
        Activate "sava{sv}" reload-config 0 0 >/dev/null 2>&1 || true
}

map_has_video() {
    local o pic
    for o in $(outputs); do
        pic=$(map_get "$o")
        if [ -n "$pic" ] && [ -f "$pic" ] && is_video "$pic"; then
            return 0
        fi
    done
    return 1
}

restore_all() {
    local o pic any=false
    for o in $(outputs); do
        pic=$(map_get "$o")
        [ -n "$pic" ] && [ -f "$pic" ] || pic=$(cat "$STATE" 2>/dev/null || true)
        [ -n "$pic" ] && [ -f "$pic" ] || pic=$(pop_bag) || continue
        map_put "$o" "$pic"
        apply_visual "$pic" "$o"
        any=true
    done
    [ "$any" = true ] || exit 0
    sync_videos
    palette_update
    exit 0
}

daemon_was_running=true
awww query >/dev/null 2>&1 || daemon_was_running=false
ensure_daemon || exit 0

cmd="${1:-}"
target=""

if [ "$cmd" = "init" ]; then
    if [ ! -s "$MAP" ] && [ -s "$STATE" ]; then
        pic=$(cat "$STATE")
        [ -f "$pic" ] && map_put_all "$pic"
    fi
    if [ "$daemon_was_running" = true ]; then
        if map_has_video && ! pgrep -x mpvpaper >/dev/null 2>&1; then
            sync_videos
        fi
        exit 0
    fi
    restore_all
elif [ "$cmd" = "set" ]; then
    pic="${2:-}"
    [ -f "$pic" ] || exit 1
    target="${3:-}"
    [ "$target" = "all" ] && target=""
else
    scope=$(jq -r '.randomScope // "all"' "$flags_file" 2>/dev/null || echo all)
    if [ "$scope" = "cursor" ]; then
        target=$(cursor_output)
    fi
    pic=$(pop_bag) || exit 0
fi

[ -n "$pic" ] || exit 0

if [ -n "$target" ]; then
    map_put "$target" "$pic"
else
    map_put_all "$pic"
fi

apply_visual "$pic" "$target"
sync_videos
palette_update

