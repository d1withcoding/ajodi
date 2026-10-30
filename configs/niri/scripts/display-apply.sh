#!/bin/sh
verb=$1
out=$2

old_file="${XDG_RUNTIME_DIR:-/tmp}/ajodi-display-$out.old"
pending_file="${XDG_RUNTIME_DIR:-/tmp}/ajodi-display-$out.pending"
outputs_kdl="${XDG_CONFIG_HOME:-$HOME/.config}/niri/outputs.kdl"

snapshot_old() {
    niri msg -j outputs 2>/dev/null | jq -r --arg o "$out" '
        if type=="object" then .[$o] else (.[] | select(.name == $o)) end // empty
    ' > "$old_file"
}

case "$verb" in
apply)
    mode=$3
    position=$4
    scale=$5
    if [ ! -e "$old_file" ]; then
        snapshot_old || exit 1
    fi
    token=$(date +%s%N)
    printf '%s' "$token" > "$pending_file"

    # Temporary configuration via niri msg
    if [ -n "$mode" ] && [ "$mode" != "auto" ]; then
        niri msg output "$out" mode "$mode" 2>/dev/null || true
    fi
    if [ -n "$scale" ]; then
        niri msg output "$out" scale "$scale" 2>/dev/null || true
    fi
    if [ -n "$position" ] && [ "$position" != "auto" ]; then
        pos_x=${position%x*}
        pos_y=${position#*x}
        niri msg output "$out" position "$pos_x" "$pos_y" 2>/dev/null || true
    fi

    setsid -f sh -c '
        pending=$1
        old=$2
        token=$3
        out_name=$4
        sleep 14
        if [ "$(cat "$pending" 2>/dev/null)" = "$token" ]; then
            if [ -s "$old" ]; then
                old_mode=$(jq -r ".current_mode.width // empty | tostring + \"x\" + (.current_mode.height // empty | tostring) + \"@\" + (.current_mode.refresh_rate // empty | tostring)" "$old")
                old_scale=$(jq -r ".logical.scale // 1.0" "$old")
                [ -n "$old_mode" ] && niri msg output "$out_name" mode "$old_mode" 2>/dev/null || true
                [ -n "$old_scale" ] && niri msg output "$out_name" scale "$old_scale" 2>/dev/null || true
            fi
            rm -f "$pending" "$old"
        fi
    ' sh "$pending_file" "$old_file" "$token" "$out" >/dev/null 2>&1
    ;;
keep)
    # Write to outputs.kdl permanently
    mode=$3
    position=$4
    scale=$5
    if [ -f "$outputs_kdl" ]; then
        cat <<EOF > "$outputs_kdl"
// Output configuration for niri (Ajodi)
output "$out" {
    scale $scale
    transform "normal"
    position x=0 y=0
}
EOF
    fi
    rm -f "$pending_file" "$old_file"
    ;;
revert)
    if [ -e "$old_file" ]; then
        old_mode=$(jq -r ".current_mode.width // empty | tostring + \"x\" + (.current_mode.height // empty | tostring) + \"@\" + (.current_mode.refresh_rate // empty | tostring)" "$old_file")
        old_scale=$(jq -r ".logical.scale // 1.0" "$old_file")
        [ -n "$old_mode" ] && niri msg output "$out" mode "$old_mode" 2>/dev/null || true
        [ -n "$old_scale" ] && niri msg output "$out" scale "$old_scale" 2>/dev/null || true
    fi
    rm -f "$pending_file" "$old_file"
    ;;
*)
    exit 2
    ;;
esac

