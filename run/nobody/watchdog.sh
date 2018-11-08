#!/bin/bash

# define destination file path for qbittorrent config file
qbittorrent_config="/config/qbittorrent/config/qbittorrent.conf"

# if qbittorrent config file doesnt exist then copy default to host config volume
if [[ ! -f "${qbittorrent_config}" ]]; then

	echo "[info] qBittorrent config file doesnt exist, copying default to /config/qbittorrent/config/..."

	# copy default qbittorrent config file to /config/qbittorrent/config/
	mkdir -p /config/qbittorrent/config && cp /home/nobody/qbittorrent/config/* /config/qbittorrent/config/

else

	echo "[info] qBittorrent config file already exists, skipping copy"

fi

# force unix line endings conversion in case user edited qbittorrent.conf with notepad
dos2unix "${qbittorrent_config}"

# set default values for port and ip
qbittorrent_port="49160"
qbittorrent_ip="0.0.0.0"

# while loop to check ip and port
while true; do

	# reset triggers to negative values
	qbittorrent_running="false"
	ip_change="false"
	port_change="false"

	if [[ "${VPN_ENABLED}" == "yes" ]]; then

		# run script to check ip is valid for tunnel device (will block until valid)
		source /home/nobody/getvpnip.sh

		# if vpn_ip is not blank then run, otherwise log warning
		if [[ ! -z "${vpn_ip}" ]]; then

			# if current bind interface ip is different to tunnel local ip then re-configure qbittorrent
			if [[ "${qbittorrent_ip}" != "${vpn_ip}" ]]; then

				echo "[info] qBittorrent listening interface IP $qbittorrent_ip and VPN provider IP ${vpn_ip} different, marking for reconfigure"

				# mark as reload required due to mismatch
				ip_change="true"

			fi

			# check if qbittorrent is running, if not then skip shutdown of process
			if ! pgrep -x "qbittorrent-nox" > /dev/null; then

				echo "[info] qBittorrent not running"

			else

				echo "[info] qBittorrent running"

				# mark as qbittorrent as running
				qbittorrent_running="true"

			fi

			# run scripts to identify external ip address
			source /home/nobody/getvpnextip.sh

			if [[ "${VPN_PROV}" == "pia" ]]; then

				# run scripts to identify vpn port
				source /home/nobody/getvpnport.sh

				# if vpn port is not an integer then dont change port
				if [[ ! "${VPN_INCOMING_PORT}" =~ ^-?[0-9]+$ ]]; then

					# set vpn port to current qbittorrent port, as we currently cannot detect incoming port (line saturated, or issues with pia)
					VPN_INCOMING_PORT="${qbittorrent_port}"

					# ignore port change as we cannot detect new port
					port_change="false"

				else

					if [[ "${qbittorrent_running}" == "true" ]]; then

						# run netcat to identify if port still open, use exit code
						nc_exitcode=$(/usr/bin/nc -z -w 3 "${qbittorrent_ip}" "${qbittorrent_port}")

						if [[ "${nc_exitcode}" -ne 0 ]]; then

							echo "[info] qBittorrent incoming port closed, marking for reconfigure"

							# mark as reconfigure required due to mismatch
							port_change="true"

						fi

					fi

					if [[ "${qbittorrent_port}" != "${VPN_INCOMING_PORT}" ]]; then

						echo "[info] qBittorrent incoming port $qbittorrent_port and VPN incoming port ${VPN_INCOMING_PORT} different, marking for reconfigure"

						# mark as reconfigure required due to mismatch
						port_change="true"

					fi

				fi

			fi

			if [[ "${port_change}" == "true" || "${ip_change}" == "true" || "${qbittorrent_running}" == "false" ]]; then

				# run script to start qbittorrent, it can also perform shutdown of qbittorrent if its already running (required for port/ip change)
				source /home/nobody/qbittorrent.sh

			fi

		else

			echo "[warn] VPN IP not detected, VPN tunnel maybe down"

		fi

	else

		# check if qbittorrent is running, if not then start via qbittorrent.sh
		if ! pgrep -x "qbittorrent-nox" > /dev/null; then

			echo "[info] qBittorrent not running"

			# run script to start qbittorrent
			source /home/nobody/qbittorrent.sh

		fi

	fi

	if [[ "${DEBUG}" == "true" && "${VPN_ENABLED}" == "yes" ]]; then

		if [[ "${VPN_PROV}" == "pia" && -n "${VPN_INCOMING_PORT}" ]]; then

			echo "[debug] VPN incoming port is ${VPN_INCOMING_PORT}"
			echo "[debug] qBittorrent incoming port is ${qbittorrent_port}"

		fi

		echo "[debug] VPN IP is ${vpn_ip}"
		echo "[debug] qBittorrent IP is ${qbittorrent_ip}"

	fi

	sleep 30s

done
