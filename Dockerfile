FROM alpine

RUN apk add --update openvpn ipcalc grep
# iproute2 net-tools

COPY start.sh /usr/bin

# VOLUME ["/vpn"]

# CMD ["/bin/sh", "/usr/bin/start.sh"]
