![logo](https://raw.githubusercontent.com/rjlasko/openvpn-proxy/master/logo.png)

# openvpn-proxy
An OpenVPN client container, whose network stack is intended to be shared with other containers.

# About this container
An Alpine Linux based container, that configures components of its network stack to allow access from specified ports via the Docker host, so that sidecar containers can respond to requests from the host network, whereas all other requests through the VPN connection.  This container functions as a single purpose process, that is meant to act as a shared resource instead of an extendable image to run multiple applications simultaneously.  If the OpenVPN process ends, then all sidecar containers using its network stack will lose connectivity to all IPs not routed from the Docker host.

# Known issues
The startup process is not smart enough to detect if it is actually restarting, and as such, it attempts to configure the network stack as if it were in the initial state, even though it is not.  This causes failures during the configuration process.

# How to use this image
The following section will demonstrate how to create an `openvpn-proxy` container, and use it in conjunction with a sidecar container.

## docker-compose
The simplest way to use this image is to use a `docker-compose.yml` file.  Here is a fully configured example.

```
version: '2.1'
services:
  openvpn-proxy:
    container_name: vprox
    image: rjlasko/openvpn-proxy
    cap_add:
      - NET_ADMIN
    devices:
      - "/dev/net/tun"
    # XXX: port mappings for applications using this container's network stack are declared here
    ports:
      - 8080:8080
      - 9090:9090
    environment:
      # XXX: port mappings for applications using this container's network stack are additionally declared here
      ADDITIONAL_PORTS: "8080,9090"
      HOST_NETWORK_CIDR: "192.168.14.0/24"
      NAME_SERVERS: "209.222.18.222,84.200.69.80,37.235.1.174,1.1.1.1,209.222.18.218,37.235.1.177,84.200.70.40,1.0.0.1"
    volumes:
      - "<path to ovpn config file>:/mnt/vpn/conf.ovpn:ro"
      - "<path to ovpn auth file>:/mnt/vpn/vpn.auth:ro"

  some-service:
    container_name: someservice
    image: your/favorite-webservice
    network_mode: service:openvpn-proxy
    # XXX: normally declared ports should be declared in the 'openvpn-proxy' service
    # ports:
    #   - 8080:8080
    #   - 9090:9090
```


## Links
Most of the credit for this goes to BinHex, as this container is very much a reduction of the work found in the following repositories:
[binhex/arch-sabnzbdvpn](https://github.com/binhex/arch-sabnzbdvpn)

[binhex/arch-int-openvpn](https://github.com/binhex/arch-int-openvpn)

Credit also goes to David Personette, as some interesting bits were taken from his OpenVPN container:
[dperson/openvpn-client](https://github.com/dperson/openvpn-client)