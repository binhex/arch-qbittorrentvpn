# Application

<!-- markdownlint-disable MD033 -->

[iQbit](https://github.com/ntoporcov/iQbit)<br/>
[qBittorrent](https://www.qbittorrent.org/)<br/>
[Privoxy](http://www.privoxy.org/)<br/>
[microsocks](https://github.com/rofl0r/microsocks)<br/>
[OpenVPN](https://openvpn.net/)<br/>
[WireGuard](https://www.wireguard.com/)

## Description

qBittorrent is a bittorrent client programmed in C++ / Qt that uses libtorrent (sometimes called libtorrent-rasterbar) by Arvid Norberg. It aims to be a good alternative to all other bittorrent clients out there. qBittorrent is fast, stable and provides unicode support as well as many features.<br/>

This Docker includes OpenVPN and WireGuard to ensure a secure and private connection to the Internet, including use of iptables to prevent IP leakage when the tunnel is down. It also includes Privoxy to allow unfiltered access to index sites, to use Privoxy please point your application at `http://<host ip>:8118`.

## Build notes

Latest repo release of iQbit from official repo (self built).<br/>
Latest stable qBittorrent release from Arch Linux repo.<br/>
Latest stable Privoxy release from Arch Linux repo.<br/>
Latest stable microsocks release from GitHub.<br/>
Latest stable OpenVPN release from Arch Linux repo.<br/>
Latest stable WireGuard release from Arch Linux repo.

## Usage

```text
docker run -d \
    --cap-add=NET_ADMIN \
    -p 8081:8081 \
    -p 8080:8080 \
    -p 8118:8118 \
    -p 9118:9118 \
    -p 58946:58946 \
    -p 58946:58946/udp \
    --name=<container name> \
    -v <path for data files>:/data \
    -v <path for config files>:/config \
    -v /etc/localtime:/etc/localtime:ro \
    -e VPN_ENABLED=<yes|no> \
    -e VPN_USER=<vpn username> \
    -e VPN_PASS=<vpn password> \
    -e VPN_PROV=<pia|airvpn|protonvpn|custom> \
    -e VPN_CLIENT=<openvpn|wireguard> \
    -e VPN_OPTIONS=<additional openvpn cli options> \
    -e ENABLE_STARTUP_SCRIPTS=<yes|no> \
    -e ENABLE_PRIVOXY=<yes|no> \
    -e STRICT_PORT_FORWARD=<yes|no> \
    -e USERSPACE_WIREGUARD=<yes|no> \
    -e ENABLE_SOCKS=<yes|no> \
    -e SOCKS_USER=<socks username> \
    -e SOCKS_PASS=<socks password> \
    -e LAN_NETWORK=<lan ipv4 network>/<cidr notation> \
    -e NAME_SERVERS=<name server ip(s)> \
    -e VPN_INPUT_PORTS=<port number(s)> \
    -e VPN_OUTPUT_PORTS=<port number(s)> \
    -e DEBUG=<true|false> \
    -e WEBUI_IQBIT_PORT=<port for web interfance> \
    -e UMASK=<umask for created files> \
    -e PUID=<uid for user> \
    -e PGID=<gid for user> \
    binhex/arch-qbittorrentvpn
```

Please replace all user variables in the above command defined by <> with the correct values.

## Access qBittorrent/iQbit (web ui)

`http://<host ip>:8081/`

Username:- `admin`<br/>
Password:- randomly generated, password shown in `/config/supervisord.log`

## Access Privoxy

`http://<host ip>:8118`

## Access microsocks

`<host ip>:9118`

default credentials: admin/socks

## PIA example

```bash
docker run -d \
    --cap-add=NET_ADMIN \
    -p 8081:8081 \
    -p 8080:8080 \
    -p 8118:8118 \
    -p 9118:9118 \
    -p 58946:58946 \
    -p 58946:58946/udp \
    --name=qbittorrentvpn \
    -v /root/docker/data:/data \
    -v /root/docker/config:/config \
    -v /etc/localtime:/etc/localtime:ro \
    -e VPN_ENABLED=yes \
    -e VPN_USER=myusername \
    -e VPN_PASS=mypassword \
    -e VPN_PROV=pia \
    -e VPN_CLIENT=openvpn \
    -e ENABLE_STARTUP_SCRIPTS=no \
    -e ENABLE_PRIVOXY=yes \
    -e STRICT_PORT_FORWARD=yes \
    -e USERSPACE_WIREGUARD=no \
    -e ENABLE_SOCKS=yes \
    -e SOCKS_USER=admin \
    -e SOCKS_PASS=socks \
    -e LAN_NETWORK=192.168.1.0/24 \
    -e NAME_SERVERS=84.200.69.80,37.235.1.174,1.1.1.1,37.235.1.177,84.200.70.40,1.0.0.1 \
    -e VPN_INPUT_PORTS=1234 \
    -e VPN_OUTPUT_PORTS=5678 \
    -e DEBUG=false \
    -e WEBUI_IQBIT_PORT=8081 \
    -e UMASK=000 \
    -e PUID=0 \
    -e PGID=0 \
    binhex/arch-qbittorrentvpn
```

## OpenVPN

Please note this Docker image does not include the required OpenVPN configuration file and certificates. These will typically be downloaded from your VPN providers website (look for OpenVPN configuration files), and generally are zipped.

PIA users - The URL to download the OpenVPN configuration files and certs is:-

[PIA OpenVPN configuration](https://www.privateinternetaccess.com/openvpn/openvpn.zip)

Once you have downloaded the zip (normally a zip as they contain multiple ovpn files) then extract it to /config/openvpn/ folder (if that folder doesn't exist then start and stop the docker container to force the creation of the folder).

If there are multiple ovpn files then please delete the ones you don't want to use (normally filename follows location of the endpoint) leaving just a single ovpn file and the certificates referenced in the ovpn file (certificates will normally have a crt and/or pem extension).

## WireGuard

If you wish to use WireGuard (defined via 'VPN_CLIENT' env var value ) then due to the enhanced security and kernel integration WireGuard will require the container to be defined with privileged permissions and sysctl support, so please ensure you change the following docker options:-  <br/>

from

``` bash
    --cap-add=NET_ADMIN \
```

to

``` bash
    --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
    --privileged=true \
```

**PIA users** - The WireGuard configuration file will be auto generated and will be stored in ```/config/wireguard/wg0.conf``` AFTER the first run, if you wish to change the endpoint you are connecting to then change the ```Endpoint``` line in the config file (default is Netherlands).

**Other users** - Please download your WireGuard configuration file from your VPN provider, start and stop the container to generate the folder ```/config/wireguard/``` and then place your WireGuard configuration file in there.

## Notes

Due to Google and OpenDNS supporting EDNS Client Subnet it is recommended NOT to use either of these NS providers.
The list of default NS providers in the above example(s) is as follows:-

84.200.x.x = DNS Watch<br/>
37.235.x.x = FreeDNS<br/>
1.x.x.x = Cloudflare

---
**IMPORTANT**<br/>
Please note `VPN_INPUT_PORTS` is **NOT** to define the incoming port for the VPN, this environment variable is used to define port(s) you want to allow in to the VPN network when network binding multiple containers together, configuring this incorrectly with the VPN provider assigned incoming port COULD result in IP leakage, you have been warned!.

---
User ID (PUID) and Group ID (PGID) can be found by issuing the following command for the user you want to run the container as:-

`id <username>`

---
Due to issues with CSRF and port mapping, should you require to alter the port for the webui you need to change both sides of the -p 8080 switch AND set the WEBUI_PORT variable to the new port.

For example, to set the port to 8090 you need to set:-

```bash
    -p 8090:8090 \
```

and

```bash
    -e WEBUI_PORT=8090 \
```

---
If you are using VPN provider PIA or ProtonVPN and wish to share the assigned dynamic incoming port with another docker container running in the same network then this can be done via a docker volume, so add the following to your docker run command:-

``` bash
    -v <name of volume>:/shared \
```

e.g.

```bash
    -v binhex-shared:/shared \
```

The incoming port will then be available in `/shared/getvpnport`.

---
If you appreciate my work, then please consider buying me a beer  :D

[![PayPal donation](https://www.paypal.com/en_US/i/btn/btn_donate_SM.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=MM5E27UX6AUU4)

[Documentation](https://github.com/binhex/documentation) | [Support forum](https://forums.unraid.net/topic/75539-support-binhex-qbittorrentvpn/)
