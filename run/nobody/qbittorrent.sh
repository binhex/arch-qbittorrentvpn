#!/bin/bash

if [[ "${qbittorrent_running}" == "false" ]]; then

	echo "[info] Removing session lock file (if it exists)..."
	rm -f /config/qBittorrent/data/BT_backup/session.lock

	echo "[info] Attempting to start qBittorrent..."

	# run qBittorrent (daemonized, non-blocking) - note qbittorrent requires docker privileged flag
	/usr/bin/qbittorrent-nox --daemon --webui-port="${WEBUI_PORT}" --profile=/config

	# make sure process qbittorrent-nox DOES exist
	retry_count=30
	while true; do

		if ! pgrep -x "qbittorrent-nox" > /dev/null; then

			retry_count=$((retry_count-1))
			if [ "${retry_count}" -eq "0" ]; then

				echo "[warn] Wait for qBittorrent process to start aborted, too many retries"
				echo "[warn] Showing output from command before exit..."
				timeout 10 yes | /usr/bin/qbittorrent-nox --webui-port="${WEBUI_PORT}" --profile=/config ; exit 1

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

	echo "[info] qBittorrent process listening on port ${WEBUI_PORT}"

fi

# change incoming port using the qbittorrent api - note this requires anonymous authentication via webui
# option 'Bypass authentication for clients on localhost'
if [[ "${VPN_PROV}" == "pia" && -n "${VPN_INCOMING_PORT}" ]]; then

	if grep -qF "WebUI\HTTPS\Enabled=false" /config/qBittorrent/config/qBittorrent.conf; then
		curl -i -X POST -d "json={\"random_port\": false}" "http://localhost:${WEBUI_PORT}/api/v2/app/setPreferences" &> /dev/null
		curl -i -X POST -d "json={\"listen_port\": ${VPN_INCOMING_PORT}}" "http://localhost:${WEBUI_PORT}/api/v2/app/setPreferences" &> /dev/null
	else
		curl -k -i -X POST -d "json={\"random_port\": false}" "https://localhost:${WEBUI_PORT}/api/v2/app/setPreferences" &> /dev/null
		curl -k -i -X POST -d "json={\"listen_port\": ${VPN_INCOMING_PORT}}" "https://localhost:${WEBUI_PORT}/api/v2/app/setPreferences" &> /dev/null
	fi
	
	# set qbittorrent port to current vpn port (used when checking for changes on next run)s
	qbittorrent_port="${VPN_INCOMING_PORT}"

fi

# set qbittorrent ip to current vpn ip (used when checking for changes on next run)
qbittorrent_ip="${vpn_ip}"
