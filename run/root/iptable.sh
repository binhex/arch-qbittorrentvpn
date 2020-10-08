#!/bin/bash

# identify docker bridge interface name by looking at defult route
docker_interface=$(ip -4 route ls | grep default | xargs | grep -o -P '[^\s]+$')
if [[ "${DEBUG}" == "true" ]]; then
	echo "[debug] Docker interface defined as ${docker_interface}"
fi
# identify ip for local gateway (eth0)
default_gateway=$(ip route show default | awk '/default/ {print $3}')
echo "[info] Default route for container is ${default_gateway}"

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
iptable_mangle_exit_code="${?}"

if [[ "${iptable_mangle_exit_code}" == 0 ]]; then

	echo "[info] iptable_mangle support detected, adding fwmark for tables"

	# setup route for qbittorrent http using set-mark to route traffic for port WEBUI_PORT to lan
	echo "${WEBUI_PORT}    qbittorrent_http" >> /etc/iproute2/rt_tables
	ip rule add fwmark 1 table qbittorrent_http
	ip route add default via "${default_gateway}" table qbittorrent_http


fi

# split comma separated string into array from VPN_REMOTE_PROTOCOL env var
IFS=',' read -ra vpn_remote_protocol_list <<< "${VPN_REMOTE_PROTOCOL}"

# split comma separated string into array from VPN_REMOTE_PORT env var
IFS=',' read -ra vpn_remote_port_list <<< "${VPN_REMOTE_PORT}"

# input iptable rules
###

# set policy to drop ipv4 for input
iptables -P INPUT DROP

# set policy to drop ipv6 for input
ip6tables -P INPUT DROP 1>&- 2>&-

# accept input to/from docker containers (172.x range is internal dhcp)
iptables -A INPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -j ACCEPT

# iterate over array and add all remote vpn ports and protocols
for index in "${!vpn_remote_port_list[@]}"; do

	# change openvpn config 'tcp-client' to compatible iptables 'tcp'
	if [[ "${vpn_remote_protocol_list[$index]}" == "tcp-client" ]]; then
		vpn_remote_protocol_list="tcp"
	else
		vpn_remote_protocol_list="${vpn_remote_protocol_list[$index]}"
	fi

	# note grep -e is required to indicate no flags follow to prevent -A from being incorrectly picked up
	rule_exists=$(iptables -S | grep -e "-A INPUT -i "${docker_interface}" -p "${vpn_remote_protocol_list}" -m "${vpn_remote_protocol_list}" --sport "${vpn_remote_port_list[$index]}" -j ACCEPT")
	if [[ -z "${rule_exists}" ]]; then
		# accept input to vpn gateway
		iptables -A INPUT -i "${docker_interface}" -p "${vpn_remote_protocol_list}" --sport "${vpn_remote_port_list[$index]}" -j ACCEPT
	fi

done
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
	if [[ "${ENABLE_PRIVOXY}" == "yes" ]]; then
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

# iterate over array and add all remote vpn ports and protocols
for index in "${!vpn_remote_port_list[@]}"; do

	# change openvpn config 'tcp-client' to compatible iptables 'tcp'
	if [[ "${vpn_remote_protocol_list[$index]}" == "tcp-client" ]]; then
		vpn_remote_protocol_list="tcp"
	else
		vpn_remote_protocol_list="${vpn_remote_protocol_list[$index]}"
	fi

	# note grep -e is required to indicate no flags follow to prevent -A from being incorrectly picked up
	rule_exists=$(iptables -S | grep -e "-A OUTPUT -o "${docker_interface}" -p "${vpn_remote_protocol_list}" -m "${vpn_remote_protocol_list}" --dport "${vpn_remote_port_list[$index]}" -j ACCEPT")
	if [[ -z "${rule_exists}" ]]; then
		# accept output from vpn gateway
		iptables -A OUTPUT -o "${docker_interface}" -p "${vpn_remote_protocol_list}" --dport "${vpn_remote_port_list[$index]}" -j ACCEPT
	fi

done

# if iptable mangle is available (kernel module) then use mark
if [[ "${iptable_mangle_exit_code}" == 0 ]]; then

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
	if [[ "${ENABLE_PRIVOXY}" == "yes" ]]; then
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
