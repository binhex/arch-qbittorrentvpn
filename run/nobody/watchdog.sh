#!/usr/bin/dumb-init /bin/bash

# define destination file path for qbittorrent config file
qbittorrent_config="/config/qBittorrent/config/qBittorrent.conf"

# if qbittorrent config file doesnt exist then copy default to host config volume
if [[ ! -f "${qbittorrent_config}" ]]; then

	echo "[info] qBittorrent config file doesnt exist, copying default to /config/qBittorrent/config/..."

	# copy default qbittorrent config file to /config/qBittorrent/config/
	mkdir -p /config/qBittorrent/config && cp /home/nobody/qbittorrent/config/* /config/qBittorrent/config/

else

	echo "[info] qBittorrent config file already exists, skipping copy"

fi

echo "[info] Removing session lock file (if it exists)..."
rm -f /config/qBittorrent/data/BT_backup/session.lock

# force unix line endings conversion in case user edited qbittorrent.conf with notepad
/usr/local/bin/dos2unix.sh "${qbittorrent_config}"

# set locale to prevent 4.1.4 gui render issues if no locale set
grep -q 'General\\Locale' "${qbittorrent_config}" || sed -i '/\[Preferences\]/a General\\Locale=en' "${qbittorrent_config}"

# forcibly set allow anonymous access from localhost to api (used to change incoming port)
sed -i 's~^WebUI\\LocalHostAuth=.*~WebUI\\LocalHostAuth=false~g' "${qbittorrent_config}"

# set default values for port and ip
qbittorrent_port="6881"
qbittorrent_ip="0.0.0.0"

# define sleep period between loops
sleep_period_secs=30

# define sleep period between incoming port checks
sleep_period_incoming_port_secs=1800

# sleep period counter - used to limit number of hits to external website to check incoming port
sleep_period_counter_secs=0

# while loop to check ip and port
while true; do

	# reset triggers to negative values
	qbittorrent_running="false"
	privoxy_running="false"
	ip_change="false"
	qbittorrent_port_change="false"

	if [[ "${VPN_ENABLED}" == "yes" ]]; then

		# run script to get all required info
		source /home/nobody/preruncheck.sh

		# if vpn_ip is not blank then run, otherwise log warning
		if [[ ! -z "${vpn_ip}" ]]; then

			# if current bind interface ip is different to tunnel local ip then re-configure qbittorrent
			if [[ "${qbittorrent_ip}" != "${vpn_ip}" ]]; then

				echo "[info] qBittorrent listening interface IP ${qbittorrent_ip} and VPN provider IP ${vpn_ip} different, marking for reconfigure"

				# mark as reload required due to mismatch
				ip_change="true"

			fi

			# check if qbittorrent is running, if not then skip shutdown of process
			if ! pgrep -x "qbittorrent-nox" > /dev/null; then

				echo "[info] qBittorrent not running"

			else

				# mark as qbittorrent as running
				qbittorrent_running="true"

			fi

			if [[ "${ENABLE_PRIVOXY}" == "yes" ]]; then

				# check if privoxy is running, if not then skip shutdown of process
				if ! pgrep -fa "/usr/bin/privoxy" > /dev/null; then

					echo "[info] Privoxy not running"

				else

					# mark as privoxy as running
					privoxy_running="true"

				fi

			fi

			if [[ "${VPN_PROV}" == "pia" || "${VPN_PROV}" == "protonvpn" ]]; then

				# if vpn port is not an integer then dont change port
				if [[ ! "${VPN_INCOMING_PORT}" =~ ^-?[0-9]+$ ]]; then

					# set vpn port to current qbittorrent port, as we currently cannot detect incoming port (line saturated, or issues with pia)
					VPN_INCOMING_PORT="${qbittorrent_port}"

					# ignore port change as we cannot detect new port
					qbittorrent_port_change="false"

				else

					if [[ "${qbittorrent_running}" == "true" ]]; then

						if [ "${sleep_period_counter_secs}" -ge "${sleep_period_incoming_port_secs}" ]; then

							# run script to check incoming port is accessible
							source tools.sh
							check_incoming_port

							# reset sleep period counter
							sleep_period_counter_secs=0

						fi

					fi

					if [[ "${qbittorrent_port}" != "${VPN_INCOMING_PORT}" ]]; then

						echo "[info] qBittorrent incoming port $qbittorrent_port and VPN incoming port ${VPN_INCOMING_PORT} different, marking for reconfigure"

						# mark as reconfigure required due to mismatch
						qbittorrent_port_change="true"

					fi

				fi

			fi

			if [[ "${qbittorrent_port_change}" == "true" || "${ip_change}" == "true" || "${qbittorrent_running}" == "false" ]]; then

				# run script to start qbittorrent, it can also perform shutdown of qbittorrent if its already running (required for port/ip change)
				source /home/nobody/qbittorrent.sh

			fi

			if [[ "${ENABLE_PRIVOXY}" == "yes" ]]; then

				if [[ "${privoxy_running}" == "false" ]]; then

					# run script to start privoxy
					source /home/nobody/privoxy.sh

				fi

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

		if [[ "${ENABLE_PRIVOXY}" == "yes" ]]; then

			# check if privoxy is running, if not then start via privoxy.sh
			if ! pgrep -fa "/usr/bin/privoxy" > /dev/null; then

				echo "[info] Privoxy not running"

				# run script to start privoxy
				source /home/nobody/privoxy.sh

			fi

		fi

	fi

	if [[ "${DEBUG}" == "true" && "${VPN_ENABLED}" == "yes" ]]; then

		if [[ "${VPN_PROV}" == "pia" || "${VPN_PROV}" == "protonvpn" ]] && [[ -n "${VPN_INCOMING_PORT}" ]]; then

			echo "[debug] VPN incoming port is ${VPN_INCOMING_PORT}"
			echo "[debug] qBittorrent incoming port is ${qbittorrent_port}"

		fi

		echo "[debug] VPN IP is ${vpn_ip}"
		echo "[debug] qBittorrent IP is ${qbittorrent_ip}"

	fi

	# increment sleep period counter - used to limit number of hits to external website to check incoming port
	sleep_period_counter_secs=$((sleep_period_counter_secs+"${sleep_period_secs}"))

	sleep "${sleep_period_secs}"s

done
