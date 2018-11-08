#!/bin/bash

# kill qbittorrent (required due to the fact qbittorrent cannot cope with dynamic changes to port)
if [[ "${qbittorrent_running}" == "true" ]]; then

	# note its not currently possible to change port and/or ip address whilst running, thus the sigterm
	echo "[info] Sending SIGTERM (-15) to 'qbittorrent-nox' (will terminate qbittorrent) due to port/ip change..."

	# SIGTERM used here as SIGINT does not kill the process
	pkill -SIGTERM "qbittorrent-nox"

	# make sure 'qbittorrent-nox' process DOESNT exist before re-starting
	while pgrep -x "qbittorrent-nox" &> /dev/null
	do

		sleep 0.5s

	done

fi

echo "[info] Removing session lock file (if it exists)..."
rm -f /config/qBittorrent/data/BT_backup/session.lock

echo "[info] Attempting to start qBittorrent..."

if [[ "${VPN_ENABLED}" == "yes" ]]; then

	if [[ "${VPN_PROV}" == "pia" && -n "${VPN_INCOMING_PORT}" ]]; then

		# run qBittorrent (daemonized, non-blocking), specifying listening interface and port
		/usr/bin/qbittorrent-nox --daemon --webui-port=8080 --profile=/config --relative-fastresume

		# set qbittorrent port to current vpn port (used when checking for changes on next run)
		qbittorrent_port="${VPN_INCOMING_PORT}"

	else

		# run qBittorrent (daemonized, non-blocking), specifying listening interface
		/usr/bin/qbittorrent-nox --daemon --webui-port=8080 --profile=/config --relative-fastresume

	fi

	# set qbittorrent ip to current vpn ip (used when checking for changes on next run)
	qbittorrent_ip="${vpn_ip}"

else

	# run tmux attached to qBittorrent (daemonized, non-blocking)
	/usr/bin/qbittorrent-nox --daemon --webui-port=8080 --profile=/config --relative-fastresume

fi

# make sure process qbittorrent DOES exist
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

echo "[info] Waiting for qBittorrent process to start listening on port 8080..."

while [[ $(netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".8080"') == "" ]]; do
	sleep 0.1
done

echo "[info] qBittorrent process listening"
