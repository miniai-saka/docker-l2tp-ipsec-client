#!/bin/sh
set -eu
umask 077

fail() {
    echo "$*" >&2
    exit 1
}

peer=${VPN_ENDPOINT:?Set VPN_ENDPOINT to the VPN server IPv4 address}
case "$peer" in
    *[!0-9.]*|'') fail "VPN_ENDPOINT must be an IPv4 address" ;;
esac
test -c /dev/ppp || fail "Host /dev/ppp is required"
underlay=$(ip -4 route get "$peer")
route_field() {
    printf '%s\n' "$underlay" | awk -v key="$1" '
        { for (i = 1; i < NF; i++) if ($i == key) { print $(i+1); exit } }
    '
}
uplink=$(route_field dev)
gateway=$(route_field via)
local_ip=$(route_field src)
test "$uplink" = eth0 && test -n "$gateway" && test -n "$local_ip" ||
    fail "The VPN endpoint must be reachable via the Docker bridge gateway"

# Block Docker's DNS listener before its destination NAT can run.
iptables -w -t raw -C OUTPUT -d 127.0.0.11 -j DROP 2>/dev/null ||
    iptables -w -t raw -I OUTPUT -d 127.0.0.11 -j DROP
iptables-restore -w <<EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -i $uplink -s $peer -p udp --sport 1701 --dport 1701 -m policy --dir in --pol ipsec --proto esp --mode transport -j ACCEPT
-A INPUT -i $uplink -p udp --dport 1701 -j DROP
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A INPUT -i $uplink -s $peer -p udp -m multiport --dports 500,4500 -j ACCEPT
-A INPUT -i $uplink -s $peer -p esp -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -o ppp0 -j ACCEPT
-A OUTPUT -o $uplink -d $peer -p udp -m multiport --dports 500,4500 -j ACCEPT
-A OUTPUT -o $uplink -d $peer -p esp -j ACCEPT
-A OUTPUT -o $uplink -d $peer -p udp --sport 1701 --dport 1701 -m policy --dir out --pol ipsec --proto esp --mode transport -j ACCEPT
COMMIT
EOF
ip -4 route replace "$peer/32" via "$gateway" dev "$uplink"

run=/run/vpn
mkdir -p "$run"
psk=$(cat /run/secrets/vpn_psk)
vpn_user=$(cat /run/secrets/vpn_user)
vpn_password=$(cat /run/secrets/vpn_password)
test -n "$psk" && test -n "$vpn_user" && test -n "$vpn_password" ||
    fail "VPN credentials are incomplete"
psk_hex=$(printf '%s' "$psk" | od -An -v -tx1 | tr -d ' \n')
ppp_quote() {
    printf '%s' "$1" | sed 's/[\\"]/\\&/g'
}

cat > /etc/strongswan.conf <<'EOF'
charon {
    install_routes = no
    filelog {
        stdout {
            default = 1
        }
    }
}
EOF
cat > "$run/swanctl.conf" <<EOF
connections {
    l2tp {
        version = 1
        local_addrs = $local_ip
        remote_addrs = $peer
        proposals = aes128-sha1-modp2048
        dpd_delay = 20s
        dpd_timeout = 60s
        local {
            auth = psk
        }
        remote {
            auth = psk
        }
        children {
            l2tp {
                mode = transport
                local_ts = dynamic[udp/1701]
                remote_ts = dynamic[udp/1701]
                esp_proposals = aes128-sha1
                dpd_action = clear
            }
        }
    }
}
secrets {
    ike-l2tp {
        secret = 0x$psk_hex
    }
}
EOF
cat > "$run/xl2tpd.conf" <<EOF
[global]
listen-addr = $local_ip
port = 1701

[lac l2tp]
lns = $peer
pppoptfile = $run/ppp-options
length bit = yes
EOF
cat > "$run/ppp-options" <<EOF
user "$(ppp_quote "$vpn_user")"
password "$(ppp_quote "$vpn_password")"
noauth
refuse-pap
refuse-chap
refuse-mschap
refuse-eap
noccp
noipv6
noipdefault
nodefaultroute
ipcp-accept-local
ipcp-accept-remote
ifname ppp0
mtu 1280
mru 1280
lcp-echo-interval 10
lcp-echo-failure 3
logfd 2
EOF
unset psk psk_hex vpn_user vpn_password

active_pid=
stop() {
    if test -n "$active_pid"; then
        kill "$active_pid" 2>/dev/null || true
        wait "$active_pid" || true
    fi
    exit 0
}
trap stop INT TERM

# Restart the tunnel processes inside the existing namespace.
while :; do
    /usr/local/sbin/vpn-session &
    active_pid=$!
    wait "$active_pid" || true
    echo "Retrying L2TP/IPsec in 15 seconds."
    sleep 15 &
    active_pid=$!
    wait "$active_pid"
done
