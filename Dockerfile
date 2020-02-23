FROM alpine

RUN apk add --update openvpn ipcalc grep dos2unix bash drill
# iproute2 net-tools

COPY start.sh /usr/bin/start

VOLUME ["/mnt/config"]

CMD ["/bin/bash", "/usr/bin/start"]
