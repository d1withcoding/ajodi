#!/bin/sh
name="$1"
run="${XDG_RUNTIME_DIR:-/tmp}"
beat="$run/ajodi-$name-alive"
ref="$run/ajodi-$name-check"
sock_id="${NIRI_SOCKET:-niri}"
exec 9>"$run/${name}-${sock_id##*/}-watchdog.lock"
flock -n 9 || exit 0

while :; do
    qs -c "$name" 9>&- >/dev/null 2>&1 &
    pid=$!
    misses=0
    while kill -0 "$pid" 2>/dev/null; do
        touch "$ref"
        sleep 3
        kill -0 "$pid" 2>/dev/null || break
        if [ "$beat" -nt "$ref" ]; then
            misses=0
        else
            misses=$((misses + 1))
            if [ "$misses" -ge 2 ]; then
                echo "$(date '+%F %T') $name hung, restarted" >> "$run/ajodi-watchdog.log"
                kill -9 "$pid"
            fi
        fi
    done
    wait "$pid"
    [ -n "$NIRI_SOCKET" ] && [ -S "$NIRI_SOCKET" ] || exit 0
    sleep 1
done

