<div align="center">

<img src="assets/truenas-logo.png" alt="TrueNAS" width="300" />

### Home Lab Apps

_... managed with Docker Compose, SOPS, Renovate, and a sprinkle of GitOps_ 🤖

</div>

---

## 📖 Overview

This repo contains the Docker Compose stacks that run on my [TrueNAS](https://www.truenas.com/) home lab server. Each app lives under `services/` with its own `compose.yaml`, environment files, and SOPS-encrypted secrets. A cron-driven continuous deployment script pulls changes from this repo and redeploys apps automatically.

The setup follows [Techno Tim's guide on running Docker on TrueNAS like a pro](https://technotim.com/posts/truenas-docker-pro/) — huge thanks to him for the excellent walkthrough. Over the years I've run increasingly complex setups with Ansible and Kubernetes, but I've since settled on this simpler approach: Docker Compose on TrueNAS, straightforward CI/CD pipelines, and a handful of VMs that also pull their containers from this repo (see [`servers.yaml`](servers.yaml)).
With [GitHub Copilot](https://github.com/features/copilot) (Claude Opus & Sonnet 4.6) accelerating the migration, I was able to get everything across in just a few days. Hope you find something useful here!

---

## ✅ Benefits

- 🚀 **GitOps without Kubernetes** — Git-driven, automated deployments without the operational overhead of running a Kubernetes cluster — compose definitions stay in git, not buried in the TrueNAS UI.
- 🔐 **Secrets & automated updates** — SOPS + Age encrypts secrets at rest; Renovate automatically opens PRs for new image digests, keeping maintenance low.
- 💾 **TrueNAS-native storage** — Containers bind-mount ZFS datasets directly — no NFS in the data path, avoiding latency and corruption risks for stateful apps like databases. Each app gets its own dataset for independent snapshots and rollback.
- 🛡️ **3-2-1 backups** — ZFS snapshots, cross-pool replication, and encrypted off-site sync to Azure Blob Storage. See [docs/BACKUP.md](docs/BACKUP.md) for the full strategy.
- 🖥️ **Managed platform** — TrueNAS maintains the host OS and provides built-in container views, removing the need to manage the underlying system or add extra monitoring tooling.
- 🔧 **Flexibility** — Standard Docker Compose means the setup works with tools like Portainer or Dockge without significant rework.

---

## 🐳 Apps

| App                                                                                           | Purpose                                                        |
| --------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| [AdGuard Home](https://adguard.com/en/adguard-home/overview.html)                             | DNS filtering and ad blocking with Unbound resolver            |
| [Alloy](https://grafana.com/oss/alloy/)                                                       | Telemetry collector — host metrics, container metrics, logs    |
| [Bazarr](https://www.bazarr.media/)                                                           | Subtitle manager for Sonarr and Radarr                         |
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
| [Kromgo](https://github.com/kashalls/kromgo)                                                  | Prometheus metric badges for public status endpoints           |
| [Lidarr](https://lidarr.audio/)                                                               | Music collection manager and download automation               |
| [Matter Server](https://github.com/home-assistant-libs/python-matter-server)                  | Matter/Thread smart home device bridge                         |
| [MeTube](https://github.com/alexta69/metube)                                                  | YouTube downloader via yt-dlp with a web UI                    |
| [Mosquitto](https://mosquitto.org/)                                                           | MQTT broker for IoT device communication                       |
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

---

## 🏗️ Setup

### 1. Create the dataset structure and clone the repo

Create a nested dataset hierarchy in the TrueNAS UI for granular snapshot and backup control:

```text
vm-pool/apps          # root — holds the git repo
vm-pool/apps/services      # parent for all app datasets
vm-pool/apps/services/adguard
vm-pool/apps/services/alloy
vm-pool/apps/services/bazarr
vm-pool/apps/services/dozzle
vm-pool/apps/services/drawio
vm-pool/apps/services/echo-server
vm-pool/apps/services/esphome
vm-pool/apps/services/frigate
vm-pool/apps/services/gatus
vm-pool/apps/services/home-assistant
vm-pool/apps/services/homepage
vm-pool/apps/services/immich
vm-pool/apps/services/kromgo
vm-pool/apps/services/lidarr
vm-pool/apps/services/matter-server
vm-pool/apps/services/metube
vm-pool/apps/services/mosquitto
vm-pool/apps/services/outline
vm-pool/apps/services/plex
vm-pool/apps/services/prowlarr
vm-pool/apps/services/qbittorrent
vm-pool/apps/services/radarr
vm-pool/apps/services/sabnzbd
vm-pool/apps/services/sonarr
vm-pool/apps/services/spottarr
vm-pool/apps/services/sqlite-web
vm-pool/apps/services/traefik
vm-pool/apps/services/traefik-forward-auth
vm-pool/apps/services/tubesync
vm-pool/apps/services/unifi
vm-pool/apps/services/wmbusmeters
# ... one dataset per app
```

Then clone the repo into the root dataset:

```sh
git clone git@github.com:DevSecNinja/truenas-apps.git /mnt/vm-pool/apps
```

Because each app has its own child dataset, you can snapshot or replicate apps independently. The Compose definitions are checked into git; each app's persistent data lives in its dataset.

### 2. Add a new app

1. Create the dataset `vm-pool/apps/services/<app-name>` in the TrueNAS UI
2. Add a `services/<app-name>/compose.yaml` (and optional `compose.env` / `secret.sops.env`) to this repo

### 3. Add apps via TrueNAS Custom App (YAML)

Create a Custom App in the TrueNAS UI and use the `include` directive to point at each compose file. For example, for Traefik:

```yaml
include:
  - /mnt/vm-pool/apps/services/traefik/compose.yaml
services: {}
```

Repeat for each app under `services/`.

---

## 🔐 Secrets

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) and [Age](https://github.com/FiloSottile/age). Each app that needs secrets has a `secret.sops.env` file which is decrypted to `.env` at deploy time by the CD script.

```sh
# Encrypt
sops -e -i $(full-path)secret.sops.env

# Decrypt (manual)
sops -d $(full-path)secret.sops.env > .env
```

The Age private key is stored on the TrueNAS host and referenced via the `-k` flag in `dccd.sh`.

---

## 🔄 Continuous Deployment

The [dccd.sh](scripts/dccd.sh) script (based on [loganmarchione/dccd](https://github.com/loganmarchione/dccd)) handles GitOps-style CD:

1. Fetches the latest commit from `main`
2. Compares local and remote hashes
3. Pulls changes if they differ
4. Decrypts SOPS secrets with Age
5. Redeploys each TrueNAS app via `docker compose`

Run it as a TrueNAS cron job:

```sh
bash /mnt/vm-pool/apps/scripts/dccd.sh -d /mnt/vm-pool/apps -x shared -t -f -k /mnt/vm-pool/apps/age.key
```

### Multi-Server Deployment

Beyond TrueNAS, apps can be deployed to additional servers. Server-app mappings are defined in `servers.yaml`:

| Server   | Platform        | Apps                                                            | Purpose                                                             |
| -------- | --------------- | --------------------------------------------------------------- | ------------------------------------------------------------------- |
| svlnas   | TrueNAS         | All 26 apps                                                     | Primary home lab (TrueNAS mode)                                     |
| svlazext | Azure VM Debian | AdGuard, Cloudflared, hadiscover, Traefik, Traefik Forward Auth | DNS filtering + Unbound, Cloudflare Tunnel, and public app backends |

Each server runs its own `dccd.sh` cron job with the `-S <server>` flag:

```sh
# Example: Azure DNS server
bash /opt/apps/scripts/dccd.sh -d /opt/apps -S svlazext -k /opt/apps/age.key -x shared -f
```

See [docs/INFRASTRUCTURE.md](docs/INFRASTRUCTURE.md#multi-server-deployment) for full details on compose overrides, per-server Age keys, and Ansible integration.

---

## 🤖 Renovate

[Renovate](https://github.com/renovatebot/renovate) watches the repo for dependency updates — container image digests in compose files and the SOPS version in `dccd.sh`. When updates are found, a PR is automatically created.

---

## 📁 Structure

```sh
📁 truenas-apps
├── 📁 scripts        # CD script (dccd.sh)
└── 📁 services            # App stacks
    ├── 📁 echo-server
    ├── 📁 gatus
    ├── 📁 homepage
    ├── 📁 immich
    ├── 📁 plex
    ├── 📁 traefik
    └── 📁 shared     # Shared env files (TZ, PUID/PGID)
```

---

## 🛠️ Development

This repo uses [go-task](https://taskfile.dev) as a task runner (managed by mise). List all available commands:

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

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for testing details, commit conventions, and the release process.

---

## 🙏 Thank You

| Project                                                       | Role                                                                                                                  |
| ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| [Age](https://github.com/FiloSottile/age)                     | Encryption key provider for SOPS                                                                                      |
| [DevSecNinja/home](https://github.com/DevSecNinja/home)       | My (former) personal home repo — source of many compose configurations built up over the years                        |
| [GitHub Copilot](https://github.com/features/copilot)         | AI coding assistant (Claude Sonnet & Opus models) — code may be AI-authored but is always reviewed and verified by me |
| [Home Operations](https://discord.gg/home-operations)         | Discord community                                                                                                     |
| [Let's Encrypt](https://letsencrypt.org/)                     | Free, automated SSL certificates                                                                                      |
| [LinuxServer.io](https://www.linuxserver.io/)                 | Docker socket proxy keeping Traefik secure                                                                            |
| [loganmarchione/dccd](https://github.com/loganmarchione/dccd) | The CD script this setup is based on                                                                                  |
| [onedr0p/home-ops](https://github.com/onedr0p/home-ops)       | README inspiration & foundation for configs                                                                           |
| [SOPS](https://github.com/getsops/sops)                       | Secret encryption                                                                                                     |
| [Techno Tim](https://technotim.com/posts/truenas-docker-pro/) | The guide this setup is built on                                                                                      |
| [TrueNAS](https://www.truenas.com/)                           | The platform powering this home lab                                                                                   |
