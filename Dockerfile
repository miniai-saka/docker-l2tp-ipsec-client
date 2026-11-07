FROM alpine:3.23@sha256:f3d55900449227ae9e237ede521e7b665d53a253b42065ba90b9db9275e198ad

RUN apk add --no-cache strongswan xl2tpd ppp iproute2 iptables ca-certificates curl bind-tools
COPY --chmod=0755 vpn-entrypoint.sh /usr/local/sbin/vpn-entrypoint
COPY --chmod=0755 vpn-session.sh /usr/local/sbin/vpn-session
COPY --chmod=0755 vpn-health.sh /usr/local/sbin/vpn-health
ENTRYPOINT ["/usr/local/sbin/vpn-entrypoint"]
