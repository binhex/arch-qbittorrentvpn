FROM binhex/arch-int-vpn:latest
LABEL org.opencontainers.image.authors = "CanardConfit"
LABEL org.opencontainers.image.source = "https://github.com/CanardConfit/arch-qbittorrentvpn"

# release tag name from buildx arg
ARG RELEASETAG

# arch from buildx --platform, e.g. amd64
ARG TARGETARCH

# additional files
##################

# add supervisor conf file for app
ADD build/*.conf /etc/supervisor/conf.d/

# add bash scripts to install app
ADD build/root/*.sh /root/

# add run bash scripts
ADD run/nobody/*.sh /home/nobody/

# add pre-configured config files for nobody
ADD config/nobody/ /home/nobody/

# install app
#############

# make executable and run bash scripts to install app
RUN chmod +x /root/*.sh /home/nobody/*.sh && \
	/bin/bash /root/install.sh "${RELEASETAG}" "${TARGETARCH}" "${TARGETARCH}"

# docker settings
#################

# expose port for incoming connections (used only if vpn disabled)
EXPOSE 6881

# expose port for iqbit http
EXPOSE 8081

# expose port for qbittorrent
EXPOSE 8080

# expose port for privoxy
EXPOSE 8118

# set permissions
#################

# run script to set uid, gid and permissions
CMD ["/bin/bash", "/usr/local/bin/init.sh"]