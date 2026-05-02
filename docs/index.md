# TrueNAS Home Lab Apps

Docker Compose stacks for a [TrueNAS](https://www.truenas.com/) home lab server, managed with
SOPS, Renovate, and GitOps.

## Overview

Each app lives under `services/` with its own `compose.yaml`, environment files, and SOPS-encrypted
secrets. A cron-driven continuous deployment script pulls changes from this repo and redeploys apps
automatically — on TrueNAS and a handful of VMs (see `servers.yaml`).

The setup follows
[Techno Tim's guide on running Docker on TrueNAS like a pro](https://technotim.com/posts/truenas-docker-pro/).

## Benefits

- **GitOps without Kubernetes** — Git-driven, automated deployments without the operational
  overhead of running a Kubernetes cluster. Compose definitions stay in git, not buried in the
  TrueNAS UI.
- **Secrets & automated updates** — SOPS + Age encrypts secrets at rest; Renovate automatically
  opens PRs for new image digests, keeping maintenance low.
- **TrueNAS-native storage** — Containers bind-mount ZFS datasets directly — no NFS in the data
  path, avoiding latency and corruption risks for stateful apps like databases. Each app gets its
  own dataset for independent snapshots and rollback.
- **Managed platform** — TrueNAS maintains the host OS and provides built-in container views,
  removing the need to manage the underlying system or add extra monitoring tooling.
- **Flexibility** — Standard Docker Compose means the setup works with tools like Portainer or
  Dockge without significant rework.

## Apps

| App                                                                                           | Purpose                                                        |
| --------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| [AdGuard Home](https://adguard.com/en/adguard-home/overview.html)                             | DNS filtering and ad blocking with Unbound resolver            |
| [Bazarr](https://www.bazarr.media/)                                                           | Subtitle manager for Sonarr and Radarr                         |
| [Bitwarden Lite](https://bitwarden.com/help/install-and-deploy-lite/)                         | Self-hosted password manager (SQLite-backed, single container) |
| [Cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) | Cloudflare Tunnel agent for exposing services via edge network |
| [Dozzle](https://dozzle.dev/)                                                                 | Real-time container log viewer                                 |
| [Draw.io](https://www.drawio.com/)                                                            | Flowchart and diagram maker                                    |
| [Echo Server](https://github.com/mendhak/docker-http-https-echo)                              | HTTP echo server for testing Traefik routing                   |
| [ESPHome](https://esphome.io/)                                                                | ESP device management and firmware builder                     |
| [Frigate](https://frigate.video/)                                                             | NVR with real-time AI object detection                         |
| [Gatus](https://gatus.io/)                                                                    | Uptime monitoring with alerting and a status page              |
| [hadiscover API](https://github.com/DevSecNinja/hadiscover)                                   | Home Assistant device discovery API backend                    |
| [Home Assistant](https://www.home-assistant.io/)                                              | Open source home automation platform                           |
| [Homepage](https://gethomepage.dev/)                                                          | Customizable dashboard for home lab services                   |
| [Immich](https://immich.app/)                                                                 | Self-hosted photo and video management                         |
| [Lidarr](https://lidarr.audio/)                                                               | Music collection manager and download automation               |
| [Matter Server](https://github.com/home-assistant-libs/python-matter-server)                  | Matter/Thread smart home device bridge                         |
| [MeTube](https://github.com/alexta69/metube)                                                  | YouTube downloader via yt-dlp with a web UI                    |
| [Mosquitto](https://mosquitto.org/)                                                           | MQTT broker for IoT device communication                       |
| [OpenClaw](https://github.com/openclaw/openclaw)                                               | Self-hosted personal AI assistant and gateway                  |
| [Outline](https://www.getoutline.com/)                                                        | Knowledge base and wiki with Azure AD authentication           |
| [Plex](https://www.plex.tv/)                                                                  | Media server with hardware transcoding                         |
| [Prowlarr](https://prowlarr.com/)                                                             | Indexer manager for the arr stack                              |
| [qBittorrent](https://www.qbittorrent.org/)                                                   | BitTorrent client with web interface                           |
| [Radarr](https://radarr.video/)                                                               | Movie collection manager and download automation               |
| [SABnzbd](https://sabnzbd.org/)                                                               | Usenet download client                                         |
| [Sonarr](https://sonarr.tv/)                                                                  | TV series collection manager and download automation           |
| [Spottarr](https://github.com/Spottarr/Spottarr)                                              | Spotnet Usenet indexer                                         |
| [SQLite Web](https://github.com/coleifer/sqlite-web)                                          | SQLite database browser for Home Assistant                     |
| [Traefik](https://traefik.io/)                                                                | Reverse proxy with automatic SSL via Cloudflare DNS            |
| [Traefik Forward Auth](https://github.com/ItalyPaleAle/traefik-forward-auth)                  | SSO authentication via Microsoft Entra ID                      |
| [TubeSync](https://github.com/meeb/tubesync)                                                  | YouTube channel and playlist synchronisation                   |
| [Unifi](https://ui.com/)                                                                      | Ubiquiti network controller with MongoDB backend               |
| [wmbusmeters](https://github.com/wmbusmeters/wmbusmeters)                                     | Wireless M-Bus smart meter reader (water/gas/heat)             |

## Documentation

| Page                                      | Description                                          |
| ----------------------------------------- | ---------------------------------------------------- |
| [Architecture](ARCHITECTURE.md)           | Compose patterns, container security, networking     |
| [Infrastructure](INFRASTRUCTURE.md)       | UID/GID allocation, storage, multi-server deployment |
| [Contributing](CONTRIBUTING.md)           | Renovate, commit conventions, release process        |
| [Database Upgrades](DATABASE-UPGRADES.md) | PostgreSQL major version upgrade procedures          |
| [Disaster Recovery](DISASTER-RECOVERY.md) | Full rebuild procedures for a fresh TrueNAS          |
| [Troubleshooting](TROUBLESHOOTING.md)     | Docker, DNS, and permissions diagnostics             |
| [Retired Services](RETIRED-SERVICES.md)   | Log of retired services and last active state        |

## Development

This repo uses [go-task](https://taskfile.dev) as a task runner (managed by mise). List all
available commands:

```sh
task --list
```

Common workflows:

```sh
task test        # Run the BATS test suite (unit + integration)
task lint        # Run all linters
task format      # Auto-format all files
task ci:local    # Run the full CI pipeline locally
```

See [Contributing](CONTRIBUTING.md) for testing details, commit conventions, and the release process.
