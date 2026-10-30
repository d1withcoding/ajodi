#!/bin/sh
umask 077
dir="${XDG_RUNTIME_DIR:-/tmp}"

# Grab every monitor first so the desktop is captured while it is still live and
# on screen, then lock.
for out in $(niri msg -j outputs 2>/dev/null | jq -r 'if type=="object" then keys[] else .[].name end'); do
    [ -n "$out" ] || continue
    rm -f "$dir/ajodi-lock-$out.png"
    grim -o "$out" "$dir/ajodi-lock-$out.png" 2>/dev/null &
done
wait

# Poke the lock daemon through its file watch
date +%s%N > "$dir/ajodi-lock-trigger"

locked() {
    i=0
    while [ "$i" -lt "$1" ]; do
        [ -s "$dir/ajodi-locked" ] && return 0
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}
locked 20 && exit 0
pgrep -f "qs -c lock$" >/dev/null || setsid -f "$HOME/.config/niri/scripts/watchdog.sh" lock >/dev/null 2>&1
i=0
until qs -c lock ipc call lock lock >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -ge 30 ] && break
    sleep 0.2
done
locked 30

