#!/bin/bash

# exit script if return code != 0
set -e

# release tag name from buildx arg, stripped of build ver using string manipulation
RELEASETAG="${1}"

# target arch from buildx arg
TARGETARCH="${2}"

if [[ -z "${RELEASETAG}" ]]; then
	echo "[warn] Release tag name from build arg is empty, exiting script..."
	exit 1
fi

if [[ -z "${TARGETARCH}" ]]; then
	echo "[warn] Target architecture name from build arg is empty, exiting script..."
	exit 1
fi

# write RELEASETAG to file to record the release tag used to build the image
echo "IMAGE_RELEASE_TAG=${RELEASETAG}" >> '/etc/image-release'

# note do NOT download build scripts - inherited from int script with envvars common defined

# get target arch from Dockerfile argument
TARGETARCH="${2}"

# pacman packages
####

# call pacman db and package updater script
source upd.sh

# define pacman packages
pacman_packages="qbittorrent-nox python geoip git nodejs npm yarn"

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
#pacman -S binutils --needed --noconfirm
#strip --remove-section=.note.ABI-tag /usr/lib64/libQt5Core.so.5

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

export WEBUI_PORT=8080

export WEBUI_IQBIT_PORT=$(echo "${WEBUI_IQBIT_PORT}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${WEBUI_IQBIT_PORT}" ]]; then
	echo "[info] WEBUI_PORT defined as '${WEBUI_IQBIT_PORT}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[warn] WEBUI_IQBIT_PORT not defined (via -e WEBUI_IQBIT_PORT), defaulting to '8081'" | ts '%Y-%m-%d %H:%M:%.S'
	export WEBUI_IQBIT_PORT="8081"
fi

export APPLICATION="qbittorrent"

EOF

# replace env vars placeholder string with contents of file (here doc)
sed -i '/# ENVVARS_PLACEHOLDER/{
    s/# ENVVARS_PLACEHOLDER//g
    r /tmp/envvars_heredoc
}' /usr/local/bin/init.sh
rm /tmp/envvars_heredoc


# Installing iQbit frontend
git clone https://github.com/ntoporcov/iQbit.git /home/nobody/iqbit
cd /home/nobody/iqbit
yarn install
yarn server-setup
yarn build
cd ~

# cleanup
cleanup.sh
