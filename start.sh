#!/bin/sh
set -euo pipefail
# set -xv

# this script needs to take in all variables that will:
# 1. setup the default user
# 2. configure iptables
# 3. run openvpn (as user?)

DEBUG=${DEBUG:-"false"}

#######################
## PARSE OVPN CONFIG ##
#######################
mkdir -p /vpn
VPN_CONFIG="/vpn/vpn.conf"
if [ ! -f ${VPN_CONFIG_SRC} ] ; then
	echo "[error] Failed to find OVPN config file located at VPN_CONFIG_SRC: ${VPN_CONFIG_SRC}"
fi
dos2unix -n ${VPN_CONFIG_SRC} ${VPN_CONFIG}
echo "[info] OpenVPN config file (ovpn extension) is located at ${VPN_CONFIG}"

vpn_remote_line=$(grep -P -o -m 1 '^(\s+)?remote\s.*' $VPN_CONFIG_SRC)
echo "[info] VPN remote line defined as '${vpn_remote_line}'"

VPN_REMOTE=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '(?<=remote\s)[^\s]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
echo "[info] VPN_REMOTE defined as '${VPN_REMOTE}'"

VPN_PORT=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '\d{2,5}(\s?)+(tcp|udp|tcp-client)?$' | grep -P -o -m 1 '\d+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
echo "[info] VPN_PORT defined as '${VPN_PORT}'"

VPN_PROTOCOL=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^proto\s)[^\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
echo "[info] VPN_PROTOCOL defined as '${VPN_PROTOCOL}'"

VPN_DEVICE_TYPE=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^dev\s)[^\r\n\d]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
VPN_DEVICE_TYPE="${VPN_DEVICE_TYPE}0"
echo "[info] VPN_DEVICE_TYPE defined as '${VPN_DEVICE_TYPE}'"

NAME_SERVERS=$(echo "${NAME_SERVERS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
echo "[info] NAME_SERVERS defined as '${NAME_SERVERS}'"

#########################
## DOCKER NETWORK INFO ##
#########################

# identify docker bridge interface name (probably eth0)
docker_interface=$(ip -family inet address | grep -vE "lo|tun|tap" | sed -n '1!p' | head -n 1 | cut -d ':' -f 2 | cut -d '@' -f 0 | xargs)
echo "[info] Docker interface defined as ${docker_interface}"

# identify ip for docker bridge interface
docker_ip=$(ip -oneline -family inet addr show ${docker_interface} | awk '{print $4}' | cut -d '/' -f 0)
echo "[info] Docker IP defined as ${docker_ip}"

# identify netmask for docker bridge interface
docker_mask=$(ifconfig ${docker_interface} | awk '/Mask:/{print $4}' | cut -d ':' -f 2)
echo "[info] Docker netmask defined as ${docker_mask}"

# convert netmask into cidr format
docker_network_cidr=$(ipcalc "${docker_ip}" "${docker_mask}" | grep "Network" | awk '{print $2}')
echo "[info] Docker network defined as ${docker_network_cidr}"

#######################
## HOST NETWORK INFO ##
#######################

# get ip for local gateway (eth0)
default_gateway=$(ip route show default | awk '/default/ {print $3}')
echo "[info] Default route for container is ${default_gateway}"

##############
## IP ROUTE ##
##############

if [ -n "${HOST_NETWORK_CIDR:-}" ] ; then
	cidr_regex='(((25[0-5]|2[0-4][0-9]|1?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9][0-9]?))(\/([8-9]|[1-2][0-9]|3[0-2]))([^0-9.]|$)'
	# trim surrounding whitespace
	host_net_cidr=$(echo ${HOST_NETWORK_CIDR} | xargs)
	if echo ${host_net_cidr} | grep -qP "${cidr_regex}" ; then
		echo "[info] Adding ${HOST_NETWORK_CIDR} as route via docker ${docker_interface}"
		ip route add "${host_net_cidr}" via "${default_gateway}" dev "${docker_interface}"
	else
		echo "[error] Invalid syntax for HOST_NETWORK_CIDR: ${HOST_NETWORK_CIDR}"
		exit 1
	fi
fi

echo "[info] ip route defined as follows..."
echo "--------------------"
ip route
echo "--------------------"

###############
## IP TABLES ##
###############

# terminate upon detection of system components that are likely to cause errors
if lsmod | grep "iptable_mangle" ; then
	echo "[error] Detected kernel module 'iptable_mangle', which is currently unhandled by this image! See the following URLs for how to handle:"
	echo "[info] https://github.com/binhex/arch-sabnzbdvpn/blob/47b6521fc3f73be2ec1302941e1da8ffb6139956/run/root/iptable.sh#L63"
	echo "[info] https://github.com/binhex/arch-sabnzbdvpn/blob/47b6521fc3f73be2ec1302941e1da8ffb6139956/run/root/iptable.sh#L171"
	exit 1
fi
if which ip6tables ; then
	echo "[error] Detected command 'ip6tables'! IPv6 is currently unhandled by this image. See the following URLs for how to handle:"
	echo "[info] https://github.com/binhex/arch-sabnzbdvpn/blob/47b6521fc3f73be2ec1302941e1da8ffb6139956/run/root/iptable.sh#L86"
	echo "[info] https://github.com/binhex/arch-sabnzbdvpn/blob/47b6521fc3f73be2ec1302941e1da8ffb6139956/run/root/iptable.sh#L153"
	echo "[info] https://github.com/binhex/arch-sabnzbdvpn/blob/47b6521fc3f73be2ec1302941e1da8ffb6139956/run/root/iptable.sh#L162"
	exit 1
fi

# set default behaviors for IPv4 policy chains to DROP
iptables --policy INPUT DROP
iptables --policy FORWARD DROP
iptables --policy OUTPUT DROP

# accept input to, and output from, docker containers (172.x.y.z is typical internal DHCP)
iptables --append INPUT --source "${docker_network_cidr}" --destination "${docker_network_cidr}" --jump ACCEPT
iptables --append OUTPUT --source "${docker_network_cidr}" --destination "${docker_network_cidr}" --jump ACCEPT

# accept input to, and output from, VPN gateway
iptables --append INPUT --in-interface "${docker_interface}" --protocol ${VPN_PROTOCOL} --source-port ${VPN_PORT} --jump ACCEPT
iptables --append OUTPUT --out-interface "${docker_interface}" --protocol ${VPN_PROTOCOL} --destination-port ${VPN_PORT} --jump ACCEPT

# XXX: need to understand why VPN_PORT specifies [INPUT, --source-port] & [OUTPUT, --destination-port]
# while all other ports specify source and destination ports for both INPUT and OUTPUT

# FIXME: requires bash
# if [[ ! -z "${ADDITIONAL_PORTS:-}" ]] ; then
# 	# split comma separated string into list from ADDITIONAL_PORTS env variable
# 	IFS=',' read -ra additional_port_list <<< "${ADDITIONAL_PORTS}"
# 
# 	# process additional ports in the list
# 	for additional_port_item in "${additional_port_list[@]}" ; do
# 		# strip whitespace from start and end of additional_port_item
# 		additional_port_item=$(echo "${additional_port_item}" | xargs)
# 
# 		echo "[info] Adding additional incoming & outgoing port ${additional_port_item} for ${docker_interface}"
# 
# 		# accept input & output to additional port for lan interface
# 		iptables --append INPUT --in-interface "${docker_interface}" --protocol tcp --destination-port "${additional_port_item}" --jump ACCEPT
# 		iptables --append INPUT --in-interface "${docker_interface}" --protocol tcp --source-port "${additional_port_item}" --jump ACCEPT
# 		iptables --append OUTPUT --out-interface "${docker_interface}" --protocol tcp --destination-port "${additional_port_item}" --jump ACCEPT
# 		iptables --append OUTPUT --out-interface "${docker_interface}" --protocol tcp --source-port "${additional_port_item}" --jump ACCEPT
# 	done
# fi

if [[ -n "${HOST_NETWORK_CIDR:-}" ]] ; then
	echo "[info] Adding HOST_NETWORK_CIDR ${host_net_cidr} via ${docker_network_cidr}"
	iptables --append INPUT --in-interface "${docker_interface}" --protocol tcp --source "${host_net_cidr}" --destination "${docker_network_cidr}" --jump ACCEPT
	iptables --append OUTPUT --out-interface "${docker_interface}" --protocol tcp --source "${docker_network_cidr}" --destination "${host_net_cidr}" --jump ACCEPT
fi

# accept input/output for icmp (ping)
iptables --append INPUT --protocol icmp --icmp-type echo-reply --jump ACCEPT
iptables --append OUTPUT --protocol icmp --icmp-type echo-request --jump ACCEPT

# accept input/output for local loopback adapter
iptables --append INPUT --in-interface lo --jump ACCEPT
iptables --append OUTPUT --out-interface lo --jump ACCEPT

# accept input/output for tunnel adapter
iptables --append INPUT --in-interface "${VPN_DEVICE_TYPE}" --jump ACCEPT
iptables --append OUTPUT --out-interface "${VPN_DEVICE_TYPE}" --jump ACCEPT

echo "[info] iptables defined as follows..."
echo "--------------------"
iptables --list-rules 2>&1 | tee /tmp/getiptables
chmod +r /tmp/getiptables
echo "--------------------"



#############
## OpenVPN ##
#############
# openvpn --config ${VPN_CONFIG}
