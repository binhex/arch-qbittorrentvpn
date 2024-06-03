# binhex/arch-qbittorrentvpn

## **Description**

qBittorrent is a BitTorrent client programmed in C++ / Qt that uses `libtorrent` (sometimes called `libtorrent-rasterbar`) by Arvid Norberg. It aims to be a good alternative to all other BitTorrent clients out there. qBittorrent is fast, stable and provides unicode support as well as many features.

This Docker includes OpenVPN and WireGuard to ensure a secure and private connection to the Internet, including the use of iptables to prevent IP leakage when the tunnel is down. It also includes Privoxy to allow unfiltered access to index sites, to use Privoxy please point your application at `http://<host ip>:8118`.

## What is in the container

<table>
    <thead>
        <tr>
            <th width="500px">Application</th>
            <th width="500px">Build Notes</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td><a href="https://www.qbittorrent.org/">qBittorrent</a></td>
            <td><strong>Latest stable</strong> qBittorrent release from Arch Linux repo.</td>
        </tr>
        <tr>
            <td><a href="http://www.privoxy.org/">Privoxy</a></td>
            <td><strong>Latest stable</strong> Privoxy release from Arch Linux repo.</td>
        </tr>
        <tr>
            <td><a href="https://openvpn.net/">OpenVPN</a></td>
            <td><strong>Latest stable</strong> OpenVPN release from Arch Linux repo.</td>
        </tr>
        <tr>
            <td><a href="https://www.wireguard.com/">WireGuard</a></td>
            <td><strong>Latest stable</strong> WireGuard release from Arch Linux repo.</td>
        </tr>
    </tbody>
</table>

## **Usage**

### Docker Run

```bash
docker run -d \
    --cap-add=NET_ADMIN \
    -p 6881:6881 \
    -p 6881:6881/udp \
    -p 8080:8080 \
    -p 8118:8118 \
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
    -e STRICT_PORT_FORWARD=<yes|no> \
    -e ENABLE_PRIVOXY=<yes|no> \
    -e ENABLE_STARTUP_SCRIPTS=<yes|no> \
    -e LAN_NETWORK=<lan ipv4 network>/<cidr notation> \
    -e NAME_SERVERS=<name server ip(s)> \
    -e VPN_INPUT_PORTS=<port number(s)> \
    -e VPN_OUTPUT_PORTS=<port number(s)> \
    -e DEBUG=<true|false> \
    -e WEBUI_PORT=<port for web interfance> \
    -e UMASK=<umask for created files> \
    -e PUID=<uid for user> \
    -e PGID=<gid for user> \
    binhex/arch-qbittorrentvpn
```

Please replace all user variables in the above command defined by <> with the correct values.

### Docker Compose (docker-compose.yml)

```yaml
services:
  qbittorrentvpn:
    image: binhex/arch-qbittorrentvpn:latest
    container_name: qbittorrentvpn
    net_cap:
      - NET_ADMIN
    environment:
      - VPN_ENABLED=<yes|no>
      - LAN_NETWORK=<lan ipv4 network>/<cidr notation>
      - VPN_USER=<vpn username>
      - VPN_PASS=<vpn password>
      - VPN_PROV=<pia|airvpn|protonvpn|custom>
      - VPN_CLIENT=<openvpn|wireguard>
      - ENABLE_PRIVOXY=<yes|no>
    volumes:
      - <path for config files>:/config
      - <path for data files>:/data
      - <path for wireguard.conf>:/config/wireguard
    ports:
      - 8080:8080
      - 6881:6881
      - 6881:6881/udp
      - 8118:8118
    restart: unless-stopped
    healthcheck:
      test: [ CMD, curl, -f, http://localhost:6881 ]
      interval: 60s
      timeout: 10s
      retries: 5
```

Please replace all user variables in the above command defined by <> with the correct values.

Once values are added you can spin up the container using `docker compose up -d`

## Access qBittorrent (WebUI)

`http://<host ip>:8080/`

Username: `admin`<br>
Password: randomly generated, password shown in `/config/supervisord.log`

## Access Privoxy

`http://<host ip>:8118`

## Port Forwarding
Port forwarding will need to be specified in qBittorrent (for some VPN providers, i.e. **not PIA**). Generally, it is better practice to use the [WebUI](#access-qbittorrent-webui) to configure this port under: 
`Tools->Options->Connection`

![image](https://github.com/binhex/arch-qBitTorrentVPN/assets/872224/bcad7fc2-94a2-464a-8e3a-7fa3eae9a3c7)

Then enter the port.

![image](https://github.com/binhex/arch-qBitTorrentVPN/assets/872224/f83e7395-1da0-4fc3-841f-f185ea6d6798)

Alternatively, you can configure it via the filesystem located at `/config/qbittorrent/config/qbittorrent.conf`.

### Example qBittorrent.conf
```
session\Port=49400
```

## IMPORTANT Note On VPN_INPUT_PORTS!

Please note 'VPN_INPUT_PORTS' is **NOT** to define the incoming port for the VPN, this environment variable is used to define port(s) you want to allow into the VPN network when network binding multiple containers together, configuring this incorrectly with the VPN provider assigned incoming port COULD result in IP leakage, you have been warned!.

## OpenVPN

_Please note_, this Docker image does not include the required OpenVPN configuration file and certificates. These will typically be downloaded from your VPN provider's website (look for OpenVPN configuration files), and generally are zipped.

Once you have downloaded the zip (normally a zip as they contain multiple ovpn files) then extract it to /config/openvpn/ folder (if that folder doesn't exist then start and stop the docker container to force the creation of the folder).

If there are multiple ovpn files then please delete the ones you don't want to use (normally filename follows the location of the endpoint) leaving just a single ovpn file and the certificates referenced in the ovpn file (certificates will normally have a crt and/or pem extension).

## WireGuard

If you wish to use WireGuard (defined via 'VPN_CLIENT' env var value ) then due to the enhanced security and kernel integration WireGuard will require the container to be defined with privileged permissions and sysctl support, so please ensure you change the following docker options:-

from
```
    --cap-add=NET_ADMIN \
```
to
```
    --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
    --privileged=true \
```

### Wireguard Note

Non-PIA Users - please download your WireGuard configuration file from your VPN provider, start and stop the container to generate the folder ```/config/wireguard/``` and then place your WireGuard configuration file in there.

## **DNS Note**
Due to Google and OpenDNS supporting EDNS Client Subnet, it is recommended NOT to use either of these NS providers.
The list of default NS providers in the above example(s) is as follows:-

84.200.x.x = DNS Watch
37.235.x.x = FreeDNS
1.x.x.x = Cloudflare

## PUID/PGID
User ID (PUID) and Group ID (PGID) can be found by issuing the following command for the user you want to run the container as:-

`id <username>`

## Note on port matching

Due to issues with CSRF and port mapping, should you require to alter the port for the WebUI you need to change both sides of the -p 8080 switch AND set the WEBUI_PORT variable to the new port.

For example, to set the port to 8090 you need to set -p 8090:8090 and -e WEBUI_PORT=8090

---

## Provider Specific Examples

### PIA

#### Docker Run

```
docker run -d \
    --cap-add=NET_ADMIN \
    -p 6881:6881 \
    -p 6881:6881/udp \
    -p 8080:8080 \
    -p 8118:8118 \
    --name=qbittorrentvpn \
    -v /root/docker/data:/data \
    -v /root/docker/config:/config \
    -v /etc/localtime:/etc/localtime:ro \
    -e VPN_ENABLED=yes \
    -e VPN_USER=myusername \
    -e VPN_PASS=mypassword \
    -e VPN_PROV=pia \
    -e VPN_CLIENT=openvpn \
    -e STRICT_PORT_FORWARD=yes \
    -e ENABLE_PRIVOXY=yes \
    -e ENABLE_STARTUP_SCRIPTS=no \
    -e LAN_NETWORK=192.168.1.0/24 \
    -e NAME_SERVERS=84.200.69.80,37.235.1.174,1.1.1.1,37.235.1.177,84.200.70.40,1.0.0.1 \
    -e VPN_INPUT_PORTS=1234 \
    -e VPN_OUTPUT_PORTS=5678 \
    -e DEBUG=false \
    -e WEBUI_PORT=8080 \
    -e UMASK=000 \
    -e PUID=0 \
    -e PGID=0 \
    binhex/arch-qbittorrentvpn
```

#### Open VPN Notes

PIA users - The URL to download the OpenVPN configuration files and certs is:-

https://www.privateinternetaccess.com/openvpn/openvpn.zip

#### Wireguard Notes

PIA users - The WireGuard configuration file will be auto-generated and will be stored in ```/config/wireguard/wg0.conf``` AFTER the first run, if you wish to change the endpoint you are connecting to then change the ```Endpoint``` line in the config file (default is Netherlands).

### AirVPN

#### Docker Run

```
docker run -d \
    --cap-add=NET_ADMIN \
    -p 6881:6881 \
    -p 6881:6881/udp \
    -p 8080:8080 \
    -p 8118:8118 \
    --name=qbitTorrentvpn \
    -v /root/docker/data:/data \
    -v /root/docker/config:/config \
    -v /etc/localtime:/etc/localtime:ro \
    -e VPN_ENABLED=yes \
    -e VPN_PROV=airvpn \
    -e VPN_CLIENT=openvpn \
    -e ENABLE_PRIVOXY=yes \
    -e ENABLE_STARTUP_SCRIPTS=no \
    -e LAN_NETWORK=192.168.1.0/24 \
    -e NAME_SERVERS=84.200.69.80,37.235.1.174,1.1.1.1,37.235.1.177,84.200.70.40,1.0.0.1 \
    -e VPN_INPUT_PORTS=1234 \
    -e VPN_OUTPUT_PORTS=5678 \
    -e DEBUG=false \
    -e WEBUI_PORT=8080 \
    -e UMASK=000 \
    -e PUID=0 \
    -e PGID=0 \
    binhex/arch-qbittorrentvpn
```

#### Open VPN Configuration

AirVPN users will need to generate a unique OpenVPN configuration file by using the following link https://airvpn.org/generator/

1. Please select Linux and then choose the country you want to connect to
2. Save the ovpn file to somewhere safe
3. Start the qBitTorrentVPN docker to create the folder structure
4. Stop qBitTorrentVPN docker and copy the saved ovpn file to the /config/openvpn/ folder on the host
5. Start qBitTorrentVPN docker
6. Check supervisor.log to make sure you are connected to the tunnel

#### Port Forwarding

AirVPN users will also need to create a port forward by using the following link https://airvpn.org/ports/ and clicking Add.

___
If you appreciate my work, then please consider buying me a beer  :D

[![PayPal donation](https://www.paypal.com/en_US/i/btn/btn_donate_SM.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=MM5E27UX6AUU4)

[Documentation](https://github.com/binhex/documentation) | [Support forum](https://forums.unraid.net/topic/75539-support-binhex-qbittorrentvpn/)
