FROM alpine

RUN mkdir /vpn

ENV VPN_CONFIG_MNT ''
ENV VPN_AUTH_MNT ''
ENV HOST_NETWORK_CIDR ''
ENV NAME_SERVERS ''

RUN apk add --update openvpn ipcalc grep dos2unix bash drill
# iproute2 net-tools

COPY start.sh /usr/bin/start

CMD ["/bin/bash", "/usr/bin/start"]
