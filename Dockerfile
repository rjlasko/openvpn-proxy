FROM alpine

RUN apk add --update openvpn ipcalc grep dos2unix
# iproute2 net-tools

COPY start.sh /usr/bin

VOLUME ["/mnt/config"]

# CMD ["/bin/sh", "/usr/bin/start.sh"]
