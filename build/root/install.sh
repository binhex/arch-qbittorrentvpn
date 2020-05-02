#!/bin/bash

# exit script if return code != 0
set -e

# build scripts
####

# download build scripts from github
curl --connect-timeout 5 --max-time 600 --retry 5 --retry-delay 0 --retry-max-time 60 -o /tmp/scripts-master.zip -L https://github.com/binhex/scripts/archive/master.zip

# unzip build scripts
unzip /tmp/scripts-master.zip -d /tmp

# move shell scripts to /root
mv /tmp/scripts-master/shell/arch/docker/*.sh /usr/local/bin/

# detect image arch
####

OS_ARCH=$(cat /etc/os-release | grep -P -o -m 1 "(?=^ID\=).*" | grep -P -o -m 1 "[a-z]+$")
if [[ ! -z "${OS_ARCH}" ]]; then
	if [[ "${OS_ARCH}" == "arch" ]]; then
		OS_ARCH="x86-64"
	else
		OS_ARCH="aarch64"
	fi
	echo "[info] OS_ARCH defined as '${OS_ARCH}'"
else
	echo "[warn] Unable to identify OS_ARCH, defaulting to 'x86-64'"
	OS_ARCH="x86-64"
fi

# pacman packages
####

# call pacman db and package updater script
source upd.sh

# define pacman packages
pacman_packages="qbittorrent-nox python geoip"

# install compiled packages using pacman
if [[ ! -z "${pacman_packages}" ]]; then
	pacman -S --needed $pacman_packages --noconfirm
fi

# aur packages
####

# define aur packages
aur_packages=""

# call aur install script (arch user repo) - note true required due to autodl-irssi error during install
source aur.sh

# custom
####

# this is a (temporary?) hack to prevent the error '/usr/bin/qbittorrent-nox: 
# error while loading shared libraries: libQt5Core.so.5: cannot open shared 
# object file: No such file or directory.' when running this container on 
# hosts with older kernels (centos, mac os). alternative workaround to this
# is for the user to upgrade the kernel on their host.
pacman -S binutils --needed --noconfirm
strip --remove-section=.note.ABI-tag /usr/lib64/libQt5Core.so.5

# container perms
####

# define comma separated list of paths 
install_paths="/etc/privoxy,/home/nobody"

# split comma separated string into list for install paths
IFS=',' read -ra install_paths_list <<< "${install_paths}"

# process install paths in the list
for i in "${install_paths_list[@]}"; do

	# confirm path(s) exist, if not then exit
	if [[ ! -d "${i}" ]]; then
		echo "[crit] Path '${i}' does not exist, exiting build process..." ; exit 1
	fi

done

# convert comma separated string of install paths to space separated, required for chmod/chown processing
install_paths=$(echo "${install_paths}" | tr ',' ' ')

# set permissions for container during build - Do NOT double quote variable for install_paths otherwise this will wrap space separated paths as a single string
chmod -R 775 ${install_paths}

# create file with contents of here doc, note EOF is NOT quoted to allow us to expand current variable 'install_paths'
# we use escaping to prevent variable expansion for PUID and PGID, as we want these expanded at runtime of init.sh
cat <<EOF > /tmp/permissions_heredoc

# get previous puid/pgid (if first run then will be empty string)
previous_puid=\$(cat "/root/puid" 2>/dev/null || true)
previous_pgid=\$(cat "/root/pgid" 2>/dev/null || true)

# if first run (no puid or pgid files in /tmp) or the PUID or PGID env vars are different 
# from the previous run then re-apply chown with current PUID and PGID values.
if [[ ! -f "/root/puid" || ! -f "/root/pgid" || "\${previous_puid}" != "\${PUID}" || "\${previous_pgid}" != "\${PGID}" ]]; then

	# set permissions inside container - Do NOT double quote variable for install_paths otherwise this will wrap space separated paths as a single string
	chown -R "\${PUID}":"\${PGID}" ${install_paths}

fi

# write out current PUID and PGID to files in /root (used to compare on next run)
echo "\${PUID}" > /root/puid
echo "\${PGID}" > /root/pgid

EOF

# replace permissions placeholder string with contents of file (here doc)
sed -i '/# PERMISSIONS_PLACEHOLDER/{
    s/# PERMISSIONS_PLACEHOLDER//g
    r /tmp/permissions_heredoc
}' /usr/local/bin/init.sh
rm /tmp/permissions_heredoc

# env vars
####

cat <<'EOF' > /tmp/envvars_heredoc

# check for presence of network interface docker0
check_network=$(ifconfig | grep docker0 || true)

# if network interface docker0 is present then we are running in host mode and thus must exit
if [[ ! -z "${check_network}" ]]; then
	echo "[crit] Network type detected as 'Host', this will cause major issues, please stop the container and switch back to 'Bridge' mode" | ts '%Y-%m-%d %H:%M:%.S' && exit 1
fi

export VPN_ENABLED=$(echo "${VPN_ENABLED}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${VPN_ENABLED}" ]]; then
	if [ "${VPN_ENABLED}" != "no" ] && [ "${VPN_ENABLED}" != "No" ] && [ "${VPN_ENABLED}" != "NO" ]; then
		export VPN_ENABLED="yes"
		echo "[info] VPN_ENABLED defined as '${VPN_ENABLED}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		export VPN_ENABLED="no"
		echo "[info] VPN_ENABLED defined as '${VPN_ENABLED}'" | ts '%Y-%m-%d %H:%M:%.S'
		echo "[warn] !!IMPORTANT!! VPN IS SET TO DISABLED', YOU WILL NOT BE SECURE" | ts '%Y-%m-%d %H:%M:%.S'
	fi
else
	echo "[warn] VPN_ENABLED not defined,(via -e VPN_ENABLED), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
	export VPN_ENABLED="yes"
fi

if [[ $VPN_ENABLED == "yes" ]]; then

	# create directory to store openvpn config files
	mkdir -p /config/openvpn

	# set perms and owner for files in /config/openvpn directory
	set +e
	chown -R "${PUID}":"${PGID}" "/config/openvpn" &> /dev/null
	exit_code_chown=$?
	chmod -R 775 "/config/openvpn" &> /dev/null
	exit_code_chmod=$?
	set -e

	if (( ${exit_code_chown} != 0 || ${exit_code_chmod} != 0 )); then
		echo "[warn] Unable to chown/chmod /config/openvpn/, assuming SMB mountpoint" | ts '%Y-%m-%d %H:%M:%.S'
	fi

	# force removal of mac os resource fork files in ovpn folder
	rm -rf /config/openvpn/._*.ovpn

	# wildcard search for openvpn config files (match on first result)
	export VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print -quit)

	# if ovpn file not found in /config/openvpn then exit
	if [[ -z "${VPN_CONFIG}" ]]; then
		echo "[crit] No OpenVPN config file located in /config/openvpn/ (ovpn extension), please download from your VPN provider and then restart this container, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	echo "[info] OpenVPN config file (ovpn extension) is located at ${VPN_CONFIG}" | ts '%Y-%m-%d %H:%M:%.S'

	# convert CRLF (windows) to LF (unix) for ovpn
	/usr/local/bin/dos2unix.sh "${VPN_CONFIG}"

	# get first matching 'remote' line in ovpn
	vpn_remote_line=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '^(\s+)?remote\s.*' || true)

	if [ -n "${vpn_remote_line}" ]; then

		# remove all remote lines as we cannot cope with multi remote lines
		sed -i -E '/^(\s+)?remote\s.*/d' "${VPN_CONFIG}"

		# if remote line contains comments then remove
		vpn_remote_line=$(echo "${vpn_remote_line}" | sed -r 's~\s?+#.*$~~g')

		# if remote line contains old format 'tcp' then replace with newer 'tcp-client' format
		vpn_remote_line=$(echo "${vpn_remote_line}" | sed "s/tcp$/tcp-client/g")

		# write the single remote line back to the ovpn file on line 1
		sed -i -e "1i${vpn_remote_line}" "${VPN_CONFIG}"

		echo "[info] VPN remote line defined as '${vpn_remote_line}'" | ts '%Y-%m-%d %H:%M:%.S'

	else

		echo "[crit] VPN configuration file ${VPN_CONFIG} does not contain 'remote' line, showing contents of file before exit..." | ts '%Y-%m-%d %H:%M:%.S'
		cat "${VPN_CONFIG}" && exit 1

	fi

	export VPN_REMOTE=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '(?<=remote\s)[^\s]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_REMOTE}" ]]; then
		echo "[info] VPN_REMOTE defined as '${VPN_REMOTE}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_REMOTE not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export VPN_PORT=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '\d{2,5}(\s?)+(tcp|udp|tcp-client)?$' | grep -P -o -m 1 '\d+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_PORT}" ]]; then
		echo "[info] VPN_PORT defined as '${VPN_PORT}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_PORT not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	# if 'proto' is old format 'tcp' then forcibly set to newer 'tcp-client' format
	sed -i "s/^proto\stcp$/proto tcp-client/g" "${VPN_CONFIG}"

	export VPN_PROTOCOL=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^proto\s)[^\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_PROTOCOL}" ]]; then
		echo "[info] VPN_PROTOCOL defined as '${VPN_PROTOCOL}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		export VPN_PROTOCOL=$(echo "${vpn_remote_line}" | grep -P -o -m 1 'udp|tcp-client|tcp$' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_PROTOCOL}" ]]; then
			echo "[info] VPN_PROTOCOL defined as '${VPN_PROTOCOL}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] VPN_PROTOCOL not found in ${VPN_CONFIG}, assuming udp" | ts '%Y-%m-%d %H:%M:%.S'
			export VPN_PROTOCOL="udp"
		fi
	fi

	VPN_DEVICE_TYPE=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^dev\s)[^\r\n\d]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_DEVICE_TYPE}" ]]; then
		export VPN_DEVICE_TYPE="${VPN_DEVICE_TYPE}0"
		echo "[info] VPN_DEVICE_TYPE defined as '${VPN_DEVICE_TYPE}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_DEVICE_TYPE not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	# get values from env vars as defined by user
	export VPN_PROV=$(echo "${VPN_PROV}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_PROV}" ]]; then
		echo "[info] VPN_PROV defined as '${VPN_PROV}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_PROV not defined,(via -e VPN_PROV), exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export LAN_NETWORK=$(echo "${LAN_NETWORK}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${LAN_NETWORK}" ]]; then
		echo "[info] LAN_NETWORK defined as '${LAN_NETWORK}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] LAN_NETWORK not defined (via -e LAN_NETWORK), exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export NAME_SERVERS=$(echo "${NAME_SERVERS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${NAME_SERVERS}" ]]; then
		echo "[info] NAME_SERVERS defined as '${NAME_SERVERS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] NAME_SERVERS not defined (via -e NAME_SERVERS), defaulting to name servers defined in readme.md" | ts '%Y-%m-%d %H:%M:%.S'
		export NAME_SERVERS="209.222.18.222,84.200.69.80,37.235.1.174,1.1.1.1,209.222.18.218,37.235.1.177,84.200.70.40,1.0.0.1"
	fi

	if [[ $VPN_PROV != "airvpn" ]]; then
		export VPN_USER=$(echo "${VPN_USER}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_USER}" ]]; then
			echo "[info] VPN_USER defined as '${VPN_USER}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] VPN_USER not defined (via -e VPN_USER), assuming authentication via other method" | ts '%Y-%m-%d %H:%M:%.S'
		fi

		export VPN_PASS=$(echo "${VPN_PASS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_PASS}" ]]; then
			echo "[info] VPN_PASS defined as '${VPN_PASS}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] VPN_PASS not defined (via -e VPN_PASS), assuming authentication via other method" | ts '%Y-%m-%d %H:%M:%.S'
		fi
	fi

	export VPN_OPTIONS=$(echo "${VPN_OPTIONS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_OPTIONS}" ]]; then
		echo "[info] VPN_OPTIONS defined as '${VPN_OPTIONS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[info] VPN_OPTIONS not defined (via -e VPN_OPTIONS)" | ts '%Y-%m-%d %H:%M:%.S'
		export VPN_OPTIONS=""
	fi

	if [[ $VPN_PROV == "pia" ]]; then

		export STRICT_PORT_FORWARD=$(echo "${STRICT_PORT_FORWARD}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${STRICT_PORT_FORWARD}" ]]; then
			echo "[info] STRICT_PORT_FORWARD defined as '${STRICT_PORT_FORWARD}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] STRICT_PORT_FORWARD not defined (via -e STRICT_PORT_FORWARD), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
			export STRICT_PORT_FORWARD="yes"
		fi

	fi

	export ENABLE_PRIVOXY=$(echo "${ENABLE_PRIVOXY}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${ENABLE_PRIVOXY}" ]]; then
		echo "[info] ENABLE_PRIVOXY defined as '${ENABLE_PRIVOXY}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] ENABLE_PRIVOXY not defined (via -e ENABLE_PRIVOXY), defaulting to 'no'" | ts '%Y-%m-%d %H:%M:%.S'
		export ENABLE_PRIVOXY="no"
	fi

	export ADDITIONAL_PORTS=$(echo "${ADDITIONAL_PORTS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${ADDITIONAL_PORTS}" ]]; then
			echo "[info] ADDITIONAL_PORTS defined as '${ADDITIONAL_PORTS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
			echo "[info] ADDITIONAL_PORTS not defined (via -e ADDITIONAL_PORTS), skipping allow for custom incoming ports" | ts '%Y-%m-%d %H:%M:%.S'
	fi

fi

export WEBUI_PORT=$(echo "${WEBUI_PORT}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${WEBUI_PORT}" ]]; then
	echo "[info] WEBUI_PORT defined as '${WEBUI_PORT}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[warn] WEBUI_PORT not defined (via -e WEBUI_PORT), defaulting to '8080'" | ts '%Y-%m-%d %H:%M:%.S'
	export WEBUI_PORT="8080"
fi

export APPLICATION="qbittorrent"

EOF

# replace env vars placeholder string with contents of file (here doc)
sed -i '/# ENVVARS_PLACEHOLDER/{
    s/# ENVVARS_PLACEHOLDER//g
    r /tmp/envvars_heredoc
}' /usr/local/bin/init.sh
rm /tmp/envvars_heredoc

# cleanup
cleanup.sh
