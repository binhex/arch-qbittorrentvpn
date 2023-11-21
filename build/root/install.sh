#!/bin/bash

# exit script if return code != 0
set -e

# release tag name from buildx arg, stripped of build ver using string manipulation
RELEASETAG="${1//-[0-9][0-9]/}"

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

# note do NOT download build scripts - inherited from int script with envvars common defined

# get target arch from Dockerfile argument
TARGETARCH="${2}"

# pacman packages
####

# call pacman db and package updater script
source upd.sh

# define pacman packages
pacman_packages="python geoip"

# install compiled packages using pacman
if [[ ! -z "${pacman_packages}" ]]; then
	pacman -S --needed $pacman_packages --noconfirm
fi

# aur packages
####

# define aur packages
# note if we change this package name then ensure we also edit the PKGBUILD hack to match (see custom)
aur_packages="libtorrent-rasterbar-1_2-git"

# call aur install script (arch user repo) - note true required due to autodl-irssi error during install
source aur.sh

# custom
####

# building qbittorrent-nox package due to libtorrent-rasterbar v2 being included with aor package

# download PKGBUILD from aor package 'Source Files' (gitlab)
cd /tmp && curl -o PKGBUILD -L https://gitlab.archlinux.org/archlinux/packaging/packages/qbittorrent/-/raw/main/PKGBUILD

# edit package to use libtorrent-rasterbar-1 (installed earlier via aur.sh)
sed -i -e "s~libtorrent-rasterbar~libtorrent-rasterbar-1~g" './PKGBUILD'

# strip out restriction to not allow make as user root, used during make of aur helper
sed -i -e 's~exit $E_ROOT~~g' "/usr/bin/makepkg"

# build package
makepkg --ignorearc --clean --syncdeps --skippgpcheck --noconfirm

# install package
pacman -U qbittorrent-nox*.tar.zst --noconfirm

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
