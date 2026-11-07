#!/bin/sh
set -eu
umask 077

run=/run/vpn
charon_pid=
xl2tpd_pid=
cleanup() {
    if test -n "$xl2tpd_pid"; then
        kill "$xl2tpd_pid" 2>/dev/null || true
        wait "$xl2tpd_pid" || true
    fi
    if test -n "$charon_pid"; then
        kill "$charon_pid" 2>/dev/null || true
        wait "$charon_pid" || true
    fi
    rm -f "$run/l2tp-control" "$run/xl2tpd.pid"
}
fail() {
    echo "$*" >&2
    exit 1
}
trap 'exit 0' INT TERM
trap cleanup EXIT

/usr/lib/strongswan/charon &
charon_pid=$!
for attempt in 1 2 3 4 5; do
    swanctl --stats >/dev/null 2>&1 && break
    sleep 1
done
swanctl --load-all --noprompt --file "$run/swanctl.conf"
swanctl --initiate --child l2tp --timeout 25

xl2tpd -D -c "$run/xl2tpd.conf" -p "$run/xl2tpd.pid" -C "$run/l2tp-control" &
xl2tpd_pid=$!
for attempt in 1 2 3 4 5; do
    test -p "$run/l2tp-control" && break
    sleep 1
done
test -p "$run/l2tp-control" || fail "xl2tpd control FIFO did not start"
timeout 3 sh -c 'printf "c l2tp\n" > "$1"' sh "$run/l2tp-control"

for attempt in $(seq 1 30); do
    if ip -o -4 addr show dev ppp0 scope global 2>/dev/null | grep -q 'inet '; then
        ip -4 route replace default dev ppp0
        echo "PPP link is up. The IPv4 default route is through ppp0."
        break
    fi
    sleep 1
done
/usr/local/sbin/vpn-health || fail "L2TP/PPP setup did not finish"

while sleep 5; do
    kill -0 "$xl2tpd_pid" "$charon_pid" &&
        /usr/local/sbin/vpn-health || fail "L2TP/IPsec link lost."
done
