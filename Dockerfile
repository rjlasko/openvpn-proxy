FROM alpine

RUN apk add --update openvpn ipcalc grep
# iproute2 net-tools

COPY start.sh /usr/bin

VOLUME ["/config"]

# CMD ["/bin/sh", "/usr/bin/start.sh"]
