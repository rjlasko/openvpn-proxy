FROM alpine:latest

RUN apk add --update openvpn

COPY start.sh /usr/bin

VOLUME ["/vpn"]

CMD ["/bin/sh", "/usr/bin/start.sh"]
