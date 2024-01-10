#!/usr/bin/dumb-init /bin/bash

echo "[info] Attempting to start iqbit server..."
cd /home/nobody/iqbit
export STANDALONE_SERVER_PORT=${WEBUI_IQBIT_PORT}

npm run server-docker-start

# make sure process node iQbit DOES exist
retry_count=12
retry_wait=1
while true; do

    if ! pgrep -x "node" > /dev/null; then

        retry_count=$((retry_count-1))
        if [ "${retry_count}" -eq "0" ]; then

            echo "[warn] Wait for node iQbit process to start aborted, too many retries"
            echo "[info] Showing output from command before exit..."
            timeout 10 yes | npm run server-docker-start ; return 1

        else

            if [[ "${DEBUG}" == "true" ]]; then
                echo "[debug] Waiting for node iQbit process to start"
                echo "[debug] Re-check in ${retry_wait} secs..."
                echo "[debug] ${retry_count} retries left"
            fi
            sleep "${retry_wait}s"

        fi

    else

        echo "[info] iQbit process started"
        break

    fi

done

echo "[info] Waiting for iQbit process to start listening on port ${WEBUI_IQBIT_PORT}..."

while [[ $(netstat -lnt | awk "\$6 == \"LISTEN\" && \$4 ~ \".${WEBUI_IQBIT_PORT}\"") == "" ]]; do
    sleep 0.1
done

echo "[info] iQbit process listening on port ${WEBUI_IQBIT_PORT}"