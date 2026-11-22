# Services

Only nginx, the VPN's server (Headscale or NetBird), qBittorrent and CoreDNS publish
ports on the host. Most services are reached through nginx, at
`https://<name>.<internal-domain>`.

Services come in groups. To add a service, see
[Development](development.md#adding-a-service).

## Essential

### core

Runs on every host.

| Service | Used for | Container port | Published on host |
|---------|----------|----------------|-------------------|
| [nginx](https://github.com/nginx/nginx) | Sends each `<service>.<internal-domain>` to its service, over HTTPS | 8080, 8443 | 8080 and 8443, reached only through the port 80 and 443 redirects: from your network in local mode, from VPN devices in internet mode |
| [glance](https://github.com/glanceapp/glance) | Dashboard, at `home.<internal-domain>` | 8097 | ❌ |
| [searxng](https://github.com/searxng/searxng) | Private web search, at `search.<internal-domain>` | 8089 | ❌ |

### lan

Local mode.

| Service | Used for | Container port | Published on host |
|---------|----------|----------------|-------------------|
| [coredns](https://github.com/coredns/coredns) | DNS for the local network: `<service>.<internal-domain>` | 1053 udp+tcp | 1053, reached only through the port 53 redirect, from your network |

### netbird

Internet mode with NetBird.

| Service | Used for | Container port | Published on host |
|---------|----------|----------------|-------------------|
| [netbird-server](https://github.com/netbirdio/netbird) | NetBird's server, which your devices connect to from anywhere, at `nbs.<public-domain>` | 9443, 3478 udp | 9443 (public, through the port 443 redirect), 3478 udp (public) |
| [netbird-dashboard](https://github.com/netbirdio/dashboard) | NetBird's dashboard: users, devices and access rules, at `netbird.<internal-domain>`, from NetBird devices only | 8080 | ❌ |

Install also installs NetBird's client on the host, as a system service.

### headscale

Internet mode with Headscale.

| Service | Used for | Container port | Published on host |
|---------|----------|----------------|-------------------|
| [headscale](https://github.com/juanfont/headscale) | Headscale, which your devices connect to from anywhere with the Tailscale app, at `hs.<public-domain>` | 9443, 3478 udp | 9443 (public, through the port 443 redirect), 3478 udp (public) |

Install also installs the Tailscale client on the host, as a system service.

## Optional

### media

A media server with everything that fills its library: finding, downloading and
organizing TV shows, movies, music and audiobooks.

| Service | Used for | Container port | Published on host |
|---------|----------|----------------|-------------------|
| [jellyfin](https://github.com/jellyfin/jellyfin) | Plays your media library | 8096 | ❌ |
| [sonarr](https://github.com/Sonarr/Sonarr) | Finds and downloads TV shows | 8095 | ❌ |
| [radarr](https://github.com/Radarr/Radarr) | Finds and downloads movies | 8092 | ❌ |
| [lidarr](https://github.com/Lidarr/Lidarr) | Finds and downloads music | 8091 | ❌ |
| [listenarr](https://github.com/Listenarrs/Listenarr) | Finds and downloads audiobooks | 8090 | ❌ |
| [prowlarr](https://github.com/Prowlarr/Prowlarr) | Manages the indexers the apps above search | 8094 | ❌ |
| [flaresolverr](https://github.com/FlareSolverr/FlareSolverr) | Gets Prowlarr past Cloudflare-protected indexers | 8090 | ❌ |
| [qbittorrent](https://github.com/qbittorrent/qBittorrent) | Downloads torrents | 8093, 6881 | 6881 tcp+udp, for torrent traffic |

#### Connecting the media apps

The apps reach each other by container name, at the container ports above, and see the
shared folder `/srv/hearthbox` as `/data`:
- In Prowlarr, add FlareSolverr as an indexer proxy at `http://flaresolverr:8090`, and
  add Sonarr, Radarr and Lidarr as apps at `http://sonarr:8095`, `http://radarr:8092` and
  `http://lidarr:8091`. Prowlarr itself is at `http://prowlarr:8094`.
- In Sonarr, Radarr, Lidarr and Listenarr, the download client is qBittorrent: host
  `qbittorrent`, port `8093`.
- Downloads go to `/data/downloads` (`/srv/hearthbox/downloads` on the server).
  qBittorrent sees that folder at the same path, so the apps find what it downloaded.
- Keep your library in `/data/media` (`/srv/hearthbox/media`), one folder per kind (e.g.
  `/data/media/tv`). The apps move finished downloads there, and Jellyfin sees the same
  folder as `/media`.

### vault

Where you keep what matters: photos now; contacts, calendars, documents and passwords
coming soon.

| Service | Used for | Container port | Published on host |
|---------|----------|----------------|-------------------|
| [immich](https://github.com/immich-app/immich) | Backs up and organizes photos and videos, at `photos.<internal-domain>`. Photos are kept in `/srv/hearthbox/photos` | 8098 | ❌ |

Coming soon:

| Service | Used for |
|---------|----------|
| [radicale](https://github.com/Kozea/Radicale) | Contacts and calendars, synced with your devices |
| [paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) | Scans documents, and makes them searchable |
| [vaultwarden](https://github.com/dani-garcia/vaultwarden) | Passwords, with the Bitwarden apps |

### ai

Not picked by default. AI models that run on your server, with nothing sent elsewhere.

| Service | Used for | Container port | Published on host |
|---------|----------|----------------|-------------------|
| [ollama](https://github.com/ollama/ollama) | Downloads and runs AI models, for apps to use at `ollama.<internal-domain>`. Runs on the CPU for now | 8099 | ❌ |

### household

Coming soon.

| Service | Used for |
|---------|----------|
| [mealie](https://github.com/mealie-recipes/mealie) | Recipes, meal plans and shopping lists |
