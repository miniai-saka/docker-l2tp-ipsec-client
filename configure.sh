#!/usr/bin/env bash
set -euo pipefail
umask 077
cd -- "$(dirname -- "$0")"

host=${1:?Usage: bash configure.sh VPN_SERVER}
if [[ ! "$host" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]]; then
    echo "Enter a VPN hostname or IPv4 address." >&2
    exit 1
fi
endpoint=$(getent ahostsv4 "$host" | awk 'NR == 1 {print $1}')
test -n "$endpoint"

read -r -p 'PPP user: ' vpn_user
read -rs -p 'PPP password: ' vpn_password
printf '\n'
read -rs -p 'IPsec pre-shared key: ' vpn_psk
printf '\n'
if [[ -z "$vpn_user" || -z "$vpn_password" || -z "$vpn_psk" ]]; then
    echo "All three credentials are required." >&2
    exit 1
fi

install -d -m 700 secrets
printf '%s\n' "$vpn_user" > secrets/vpn_user
printf '%s\n' "$vpn_password" > secrets/vpn_password
printf '%s\n' "$vpn_psk" > secrets/vpn_psk
chmod 600 secrets/vpn_user secrets/vpn_password secrets/vpn_psk
printf 'VPN_ENDPOINT=%s\n' "$endpoint" > .env
printf 'VPN endpoint: %s\n' "$endpoint"
