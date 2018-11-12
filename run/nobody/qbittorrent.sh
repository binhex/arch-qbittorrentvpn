#!/bin/bash

# change incoming port using the qbittorrent api - note this requires anonymous authentication via webui
# option 'Bypass authentication for clients on localhost'
if [[ "${qbittorrent_running}" == "true" ]]; then

	if [[ "${VPN_PROV}" == "pia" && -n "${VPN_INCOMING_PORT}" ]]; then

		curl -i -X POST -d "json=%7B%22random_port%22%3Afalse%7D" "http://localhost:${WEBUI_PORT}/command/setPreferences" &> /dev/null
		curl -i -X POST -d "json=%7B%22listen_port%22%3A${VPN_INCOMING_PORT}%7D" "http://localhost:${WEBUI_PORT}/command/setPreferences" &> /dev/null
		
		# set qbittorrent port to current vpn port (used when checking for changes on next run)
		qbittorrent_port="${VPN_INCOMING_PORT}"


	fi

else

	echo "[info] Removing session lock file (if it exists)..."
	rm -f /config/qBittorrent/data/BT_backup/session.lock

	echo "[info] Attempting to start qBittorrent..."

	# run qBittorrent (daemonized, non-blocking) - note qbittorrent requires docker privileged flag
	/usr/bin/qbittorrent-nox --daemon --webui-port="${WEBUI_PORT}" --profile=/config --relative-fastresume

	# make sure process qbittorrent-nox DOES exist
	retry_count=30
	while true; do

		if ! pgrep -x "qbittorrent-nox" > /dev/null; then

			retry_count=$((retry_count-1))
			if [ "${retry_count}" -eq "0" ]; then

				echo "[warn] Wait for qBittorrent process to start aborted"
				break

			else

				if [[ "${DEBUG}" == "true" ]]; then
					echo "[debug] Waiting for qBittorrent process to start..."
				fi

				sleep 1s

			fi

		else

			echo "[info] qBittorrent process started"
			break

		fi

	done

	echo "[info] Waiting for qBittorrent process to start listening on port ${WEBUI_PORT}..."

	while [[ $(netstat -lnt | awk "\$6 == \"LISTEN\" && \$4 ~ \".${WEBUI_PORT}\"") == "" ]]; do
		sleep 0.1
	done

	# change incoming port using the qbittorrent api - note this requires anonymous authentication via webui
	# option 'Bypass authentication for clients on localhost'
	if [[ "${VPN_PROV}" == "pia" && -n "${VPN_INCOMING_PORT}" ]]; then

		curl -i -X POST -d "json=%7B%22random_port%22%3Afalse%7D" "http://localhost:${WEBUI_PORT}/command/setPreferences" &> /dev/null
		curl -i -X POST -d "json=%7B%22listen_port%22%3A${VPN_INCOMING_PORT}%7D" "http://localhost:${WEBUI_PORT}/command/setPreferences" &> /dev/null

		# set rtorrent port to current vpn port (used when checking for changes on next run)
		qbittorrent_port="${VPN_INCOMING_PORT}"

	fi

fi

# set qbittorrent ip to current vpn ip (used when checking for changes on next run)
qbittorrent_ip="${vpn_ip}"
