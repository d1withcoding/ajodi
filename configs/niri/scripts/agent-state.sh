#!/bin/sh
# Claude Code hook: notes whether a session waits for user or is done, for the pill.
[ -n "$XDG_RUNTIME_DIR" ] || exit 0
umask 077
dir="$XDG_RUNTIME_DIR/ajodi-agents"
in=$(cat)
sid=$(printf '%s' "$in" | sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p' | head -n 1)
[ -n "$sid" ] || exit 0
f="$dir/$sid.json"

case "$1" in
    wait|done)
        mkdir -p "$dir"
        cwd=$(printf '%s' "$in" | jq -r '.cwd // empty')
        cwd=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")
        msg=$(printf '%s' "$in" | jq -r '.message // empty')
        # In niri, match window by pid
        windows=$(niri msg -j windows 2>/dev/null | jq -r '.[] | "\(.pid // 0) \(.id)"')
        p=$PPID
        win_id=""
        while [ "${p:-0}" -gt 1 ]; do
            win_id=$(printf '%s\n' "$windows" | awk -v p="$p" '$1 == p { print $2; exit }')
            [ -n "$win_id" ] && break
            p=$(awk '{ print $4 }' "/proc/$p/stat" 2>/dev/null)
        done
        active_id=$(niri msg -j focused-window 2>/dev/null | jq -r '.id // empty')
        [ -n "$win_id" ] && [ "$win_id" = "$active_id" ] && { rm -f "$f"; date +%s%N > "$dir/.bump"; exit 0; }
        jq -nc --arg s "$1" --arg c "$cwd" --arg m "$msg" --arg w "$win_id" --argjson t "$(date +%s)" \
            '{status: $s, cwd: $c, message: $m, window: $w, at: $t}' > "$f.tmp" && mv "$f.tmp" "$f"
        ;;
    clear)
        grep -q '"status":"wait"' "$f" 2>/dev/null || exit 0
        rm -f "$f"
        ;;
    reset|end)
        [ -f "$f" ] || exit 0
        rm -f "$f"
        ;;
    *)
        exit 0
        ;;
esac
date +%s%N > "$dir/.bump"

