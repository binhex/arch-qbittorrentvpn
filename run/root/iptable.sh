#!/bin/bash

if [ -e /config/openvpn/vpnremotelist ] ; then
	# retrieve the VPN_REMOTE_LIST, VPN_PROTOCOL_LIST, and VPN_PORT_LIST
	readarray VPN_REMOTE_LIST < <(cat /config/openvpn/vpnremotelist | awk '{print $1}')
	readarray VPN_PORT_LIST < <(cat /config/openvpn/vpnremotelist | awk '{print $2}')
	readarray VPN_PROTOCOL_LIST < <(cat /config/openvpn/vpnremotelist | awk '{print $3}')
	for i in $(seq 0 $((${#VPN_REMOTE_LIST[@]} - 1))) ; do
		VPN_REMOTE_LIST[$i]=$(echo "${VPN_REMOTE_LIST[$i]}" | tr -d '[:space:]')
		VPN_PORT_LIST[$i]=$(echo "${VPN_PORT_LIST[$i]}" | tr -d '[:space:]')
		VPN_PROTOCOL_LIST[$i]=$(echo "${VPN_PROTOCOL_LIST[$i]}" | tr -d '[:space:]')
	done
fi

# change openvpn config 'tcp-client' to compatible iptables 'tcp'
if [ ${#VPN_PORT_LIST[@]} -gt 0 ] ; then
	for i in $(seq 0 $((${#VPN_PORT_LIST[@]} - 1))); do
		# change openvpn config 'tcp-client' to compatible iptables 'tcp'
		if [[ "${VPN_PROTOCOL_LIST[$i]}" == "tcp-client" ]]; then
			export VPN_PROTOCOL_LIST[$i]="tcp"
		fi
	done
fi
# deprecated, but make sure it's correct anyway in case it's still used
if [[ "${VPN_PROTOCOL}" == "tcp-client" ]]; then
	export VPN_PROTOCOL="tcp"
fi

# identify docker bridge interface name by looking at routing to
# vpn provider remote endpoint (first ip address from name 
# lookup in /root/start.sh
docker_interface=$(ip route show to match "${remote_dns_answer_first}" | grep -P -o -m 1 '[a-zA-Z0-9]+\s?+$' | tr -d '[:space:]')
if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Docker interface defined as ${docker_interface}"
fi

# identify ip for docker bridge interface
docker_ip=$(ifconfig "${docker_interface}" | grep -P -o -m 1 '(?<=inet\s)[^\s]+')
if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Docker IP defined as ${docker_ip}"
fi

# identify netmask for docker bridge interface
docker_mask=$(ifconfig "${docker_interface}" | grep -P -o -m 1 '(?<=netmask\s)[^\s]+')
if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Docker netmask defined as ${docker_mask}"
fi

# convert netmask into cidr format
docker_network_cidr=$(ipcalc "${docker_ip}" "${docker_mask}" | grep -P -o -m 1 "(?<=Network:)\s+[^\s]+")
echo "[info] Docker network defined as ${docker_network_cidr}"

# ip route
###

# split comma separated string into list from LAN_NETWORK env variable
IFS=',' read -ra lan_network_list <<< "${LAN_NETWORK}"

# process lan networks in the list
for lan_network_item in "${lan_network_list[@]}"; do

	# strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	echo "[info] Adding ${lan_network_item} as route via docker ${docker_interface}"
	ip route add "${lan_network_item}" via "${DEFAULT_GATEWAY}" dev "${docker_interface}"

done

echo "[info] ip route defined as follows..."
echo "--------------------"
ip route
echo "--------------------"

# setup iptables marks to allow routing of defined ports via lan
###

if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Modules currently loaded for kernel" ; lsmod
fi

# check we have iptable_mangle, if so setup fwmark
lsmod | grep iptable_mangle
iptable_mangle_exit_code=$?

if [[ $iptable_mangle_exit_code == 0 ]]; then

	echo "[info] iptable_mangle support detected, adding fwmark for tables"

	# setup route for qbittorrent http using set-mark to route traffic for port WEBUI_PORT to lan
	echo "${WEBUI_PORT}    qbittorrent_http" >> /etc/iproute2/rt_tables
	ip rule add fwmark 1 table qbittorrent_http
	ip route add default via $DEFAULT_GATEWAY table qbittorrent_http

fi

# input iptable rules
###

# set policy to drop ipv4 for input
iptables -P INPUT DROP

# set policy to drop ipv6 for input
ip6tables -P INPUT DROP 1>&- 2>&-

# accept input to/from docker containers (172.x range is internal dhcp)
iptables -A INPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -j ACCEPT

# accept input to vpn gateway for all port/protocols specified
if [ ${#VPN_PORT_LIST[@]} -gt 0 ] ; then
	for i in $(seq 0 $((${#VPN_PORT_LIST[@]} - 1))); do
		iptables -A INPUT -i "${docker_interface}" -p ${VPN_PROTOCOL_LIST[$i]} --sport ${VPN_PORT_LIST[$i]} -j ACCEPT
	done
elif [[ -n "${VPN_PROTOCOL}" ]] && [[ -n "${VPN_PORT}" ]] ; then
	iptables -A INPUT -i "${docker_interface}" -p $VPN_PROTOCOL --sport $VPN_PORT -j ACCEPT
fi

# accept input to qbittorrent port WEBUI_PORT
iptables -A INPUT -i "${docker_interface}" -p tcp --dport "${WEBUI_PORT}" -j ACCEPT
iptables -A INPUT -i "${docker_interface}" -p tcp --sport "${WEBUI_PORT}" -j ACCEPT

# additional port list for scripts or container linking
if [[ ! -z "${ADDITIONAL_PORTS}" ]]; then

	# split comma separated string into list from ADDITIONAL_PORTS env variable
	IFS=',' read -ra additional_port_list <<< "${ADDITIONAL_PORTS}"

	# process additional ports in the list
	for additional_port_item in "${additional_port_list[@]}"; do

		# strip whitespace from start and end of additional_port_item
		additional_port_item=$(echo "${additional_port_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

		echo "[info] Adding additional incoming port ${additional_port_item} for ${docker_interface}"

		# accept input to additional port for "${docker_interface}"
		iptables -A INPUT -i "${docker_interface}" -p tcp --dport "${additional_port_item}" -j ACCEPT
		iptables -A INPUT -i "${docker_interface}" -p tcp --sport "${additional_port_item}" -j ACCEPT

	done

fi

# process lan networks in the list
for lan_network_item in "${lan_network_list[@]}"; do

	# strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	# accept input to qbittorrent api - used for lan access
	iptables -A INPUT -i "${docker_interface}" -s "${lan_network_item}" -p tcp --dport "${WEBUI_PORT}" -j ACCEPT

	# accept input to privoxy if enabled
	if [[ $ENABLE_PRIVOXY == "yes" ]]; then
		iptables -A INPUT -i "${docker_interface}" -p tcp -s "${lan_network_item}" -d "${docker_network_cidr}" -j ACCEPT
	fi

done

# accept input icmp (ping)
iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT

# accept input to local loopback
iptables -A INPUT -i lo -j ACCEPT

# accept input to tunnel adapter
iptables -A INPUT -i "${VPN_DEVICE_TYPE}" -j ACCEPT

# forward iptable rules
###

# set policy to drop ipv4 for forward
iptables -P FORWARD DROP

# set policy to drop ipv6 for forward
ip6tables -P FORWARD DROP 1>&- 2>&-

# output iptable rules
###

# set policy to drop ipv4 for output
iptables -P OUTPUT DROP

# set policy to drop ipv6 for output
ip6tables -P OUTPUT DROP 1>&- 2>&-

# accept output to/from docker containers (172.x range is internal dhcp)
iptables -A OUTPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -j ACCEPT

# accept output from vpn gateway for all port/protocols specified
if [ ${#VPN_PORT_LIST[@]} -gt 0 ] ; then
	for i in $(seq 0 $((${#VPN_PORT_LIST[@]} - 1))); do
		iptables -A OUTPUT -o "${docker_interface}" -p ${VPN_PROTOCOL_LIST[$i]} --dport ${VPN_PORT_LIST[$i]} -j ACCEPT
	done
elif [[ -n "${VPN_PROTOCOL}" ]] && [[ -n "${VPN_PORT}" ]] ; then
	iptables -A OUTPUT -o "${docker_interface}" -p $VPN_PROTOCOL --dport $VPN_PORT -j ACCEPT
fi

# if iptable mangle is available (kernel module) then use mark
if [[ $iptable_mangle_exit_code == 0 ]]; then

	# accept output from qbittorrent port WEBUI_PORT - used for external access
	iptables -t mangle -A OUTPUT -p tcp --dport "${WEBUI_PORT}" -j MARK --set-mark 1
	iptables -t mangle -A OUTPUT -p tcp --sport "${WEBUI_PORT}" -j MARK --set-mark 1

fi

# accept output from qbittorrent port WEBUI_PORT - used for lan access
iptables -A OUTPUT -o "${docker_interface}" -p tcp --dport "${WEBUI_PORT}" -j ACCEPT
iptables -A OUTPUT -o "${docker_interface}" -p tcp --sport "${WEBUI_PORT}" -j ACCEPT

# additional port list for scripts or container linking
if [[ ! -z "${ADDITIONAL_PORTS}" ]]; then

	# split comma separated string into list from ADDITIONAL_PORTS env variable
	IFS=',' read -ra additional_port_list <<< "${ADDITIONAL_PORTS}"

	# process additional ports in the list
	for additional_port_item in "${additional_port_list[@]}"; do

		# strip whitespace from start and end of additional_port_item
		additional_port_item=$(echo "${additional_port_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

		echo "[info] Adding additional outgoing port ${additional_port_item} for ${docker_interface}"

		# accept output to additional port for lan interface
		iptables -A OUTPUT -o "${docker_interface}" -p tcp --dport "${additional_port_item}" -j ACCEPT
		iptables -A OUTPUT -o "${docker_interface}" -p tcp --sport "${additional_port_item}" -j ACCEPT

	done

fi

# process lan networks in the list
for lan_network_item in "${lan_network_list[@]}"; do

	# strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	# accept output to qbittorrent api - used for lan access
	iptables -A OUTPUT -o "${docker_interface}" -d "${lan_network_item}" -p tcp --sport "${WEBUI_PORT}" -j ACCEPT

	# accept output from privoxy if enabled - used for lan access
	if [[ $ENABLE_PRIVOXY == "yes" ]]; then
		iptables -A OUTPUT -o "${docker_interface}" -p tcp -s "${docker_network_cidr}" -d "${lan_network_item}" -j ACCEPT
	fi

done

# accept output for icmp (ping)
iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT

# accept output from local loopback adapter
iptables -A OUTPUT -o lo -j ACCEPT

# accept output from tunnel adapter
iptables -A OUTPUT -o "${VPN_DEVICE_TYPE}" -j ACCEPT

echo "[info] iptables defined as follows..."
echo "--------------------"
iptables -S 2>&1 | tee /tmp/getiptables
chmod +r /tmp/getiptables
echo "--------------------"

# change iptable 'tcp' back to openvpn config compatible 'tcp-client' (this file is sourced)
if [ ${#VPN_PORT_LIST[@]} -gt 0 ] ; then
	for i in $(seq 0 $((${#VPN_PORT_LIST[@]} - 1))); do
		# change openvpn config 'tcp-client' to compatible iptables 'tcp'
		if [[ "${VPN_PROTOCOL_LIST[$i]}" == "tcp" ]]; then
			export VPN_PROTOCOL_LIST[$i]="tcp-client"
		fi
	done
fi
if [[ "${VPN_PROTOCOL}" == "tcp" ]]; then
	export VPN_PROTOCOL="tcp-client"
fi
