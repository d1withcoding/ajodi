#!/bin/sh
mon=$(niri msg -j focused-output 2>/dev/null | jq -r '.name // empty')
[ -z "$mon" ] && mon=$(niri msg -j outputs 2>/dev/null | jq -r 'if type=="object" then keys[0] else .[0].name end')
qs -c pill ipc call pill quickRecord "$mon"

