#!/bin/sh
# Two headless peers play one online match through a local MQTT broker over
# WebSockets and must end on the same score. Needs amqtt (pip install amqtt);
# point AMQTT at the binary when it is not on PATH. Real time, not --fixed-fps:
# a headless WebSocketPeer drops its connection under a forced frame rate.
# Usage: sh tools/check_online.sh [godot-binary]
G=${1:-godot}
BROKER=${AMQTT:-amqtt}
RELAY=ws://127.0.0.1:1884/mqtt
CODE="T$(( $$ % 1000 ))"
tmp=$(mktemp -d)
"$BROKER" -c tools/online_broker.yaml > "$tmp/broker.log" 2>&1 &
bpid=$!
sleep 2
"$G" --headless --path . -s tests/online_peer.gd -- --role=host --code="$CODE" --relay="$RELAY" > "$tmp/host.log" 2>&1 &
hpid=$!
sleep 1
"$G" --headless --path . -s tests/online_peer.gd -- --role=guest --code="$CODE" --relay="$RELAY" > "$tmp/guest.log" 2>&1 &
gpid=$!
wait $hpid; hrc=$?
wait $gpid; grc=$?
kill $bpid 2>/dev/null
h=$(grep ONLINE_RESULT "$tmp/host.log")
g=$(grep ONLINE_RESULT "$tmp/guest.log")
echo "$h"
echo "$g"
hs=$(echo "$h" | sed -n 's/.*\(seed=[0-9]* score=[0-9-]* points=[0-9]*\).*/\1/p')
gs=$(echo "$g" | sed -n 's/.*\(seed=[0-9]* score=[0-9-]* points=[0-9]*\).*/\1/p')
if [ "$hrc" = 0 ] && [ "$grc" = 0 ] && [ -n "$hs" ] && [ "$hs" = "$gs" ]; then
	echo "online: OK ($hs, logs in $tmp)"
	exit 0
fi
echo "online: FAILED (host rc $hrc, guest rc $grc; logs in $tmp)"
grep -E "FAIL|ERROR|SCRIPT" "$tmp/host.log" "$tmp/guest.log" | head -20
exit 1
