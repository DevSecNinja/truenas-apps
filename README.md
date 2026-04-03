<div align="center">

<img src="assets/truenas-logo.png" alt="TrueNAS" width="300" />

### Home Lab Apps

_... managed with Docker Compose, SOPS, Renovate, and a sprinkle of GitOps_ 🤖

</div>

---

## 📖 Overview

This repo contains the Docker Compose stacks that run on my [TrueNAS](https://www.truenas.com/) home lab server. Each app lives under `src/` with its own `compose.yaml`, environment files, and SOPS-encrypted secrets. A cron-driven continuous deployment script pulls changes from this repo and redeploys apps automatically.

The setup follows [Techno Tim's guide on running Docker on TrueNAS like a pro](https://technotim.com/posts/truenas-docker-pro/) — huge thanks to him for the excellent walkthrough.

---

## ✅ Benefits

- 🚀 **GitOps without Kubernetes** — Git-driven, automated deployments without the operational overhead of running a Kubernetes cluster — compose definitions stay in git, not buried in the TrueNAS UI.
- 🔐 **Secrets & automated updates** — SOPS + Age encrypts secrets at rest; Renovate automatically opens PRs for new image digests, keeping maintenance low.
- 💾 **TrueNAS-native storage** — Containers bind-mount ZFS datasets directly — no NFS in the data path, avoiding latency and corruption risks for stateful apps like databases. Each app gets its own dataset for independent snapshots and rollback.
- 🖥️ **Managed platform** — TrueNAS maintains the host OS and provides built-in container views, removing the need to manage the underlying system or add extra monitoring tooling.
- 🔧 **Flexibility** — Standard Docker Compose means the setup works with tools like Portainer or Dockge without significant rework.

---

## 🐳 Apps

| App                                                                          | Purpose                                             |
| ---------------------------------------------------------------------------- | --------------------------------------------------- |
| [AdGuard Home](https://adguard.com/en/adguard-home/overview.html)            | DNS filtering and ad blocking with Unbound resolver |
| [Traefik](https://traefik.io/)                                               | Reverse proxy with automatic SSL via Cloudflare DNS |
| [Traefik Forward Auth](https://github.com/ItalyPaleAle/traefik-forward-auth) | SSO authentication via Microsoft Entra ID           |
| [Gatus](https://gatus.io/)                                                   | Uptime monitoring with alerting and a status page   |
| [Homepage](https://gethomepage.dev/)                                         | Customizable dashboard for home lab services        |
| [Echo Server](https://github.com/mendhak/docker-http-https-echo)             | HTTP echo server for testing Traefik routing        |
| [Immich](https://immich.app/)                                                | Self-hosted photo and video management              |
| [Plex](https://www.plex.tv/)                                                 | Media server with hardware transcoding              |
| [MeTube](https://github.com/alexta69/metube)                                 | YouTube downloader via yt-dlp with a web UI         |
| [Unifi](https://ui.com/)                                                     | Ubiquiti network controller with MongoDB backend    |

---

## 🏗️ Setup

### 1. Create the dataset structure and clone the repo

Create a nested dataset hierarchy in the TrueNAS UI for granular snapshot and backup control:

```text
vm-pool/apps          # root — holds the git repo
vm-pool/apps/src      # parent for all app datasets
vm-pool/apps/src/adguard
vm-pool/apps/src/traefik
vm-pool/apps/src/traefik-forward-auth
vm-pool/apps/src/gatus
vm-pool/apps/src/homepage
vm-pool/apps/src/echo-server
vm-pool/apps/src/immich
vm-pool/apps/src/plex
vm-pool/apps/src/metube
vm-pool/apps/src/unifi
# ... one dataset per app
```

Then clone the repo into the root dataset:

```sh
git clone git@github.com:DevSecNinja/truenas-apps.git /mnt/vm-pool/apps
```

Because each app has its own child dataset, you can snapshot or replicate apps independently. The Compose definitions are checked into git; each app's persistent data lives in its dataset.

### 2. Add a new app

1. Create the dataset `vm-pool/apps/src/<app-name>` in the TrueNAS UI
2. Add a `src/<app-name>/compose.yaml` (and optional `compose.env` / `secret.sops.env`) to this repo

### 3. Add apps via TrueNAS Custom App (YAML)

Create a Custom App in the TrueNAS UI and use the `include` directive to point at each compose file. For example, for Traefik:

```yaml
include:
  - /mnt/vm-pool/apps/src/traefik/compose.yaml
services: {}
```

Repeat for each app under `src/`.

---

## 🔐 Secrets

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) and [Age](https://github.com/FiloSottile/age). Each app that needs secrets has a `secret.sops.env` file which is decrypted to `.env` at deploy time by the CD script.

```sh
# Encrypt
sops -e -i secret.sops.env

# Decrypt (manual)
sops -d secret.sops.env > .env
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

---

## 🤖 Renovate

[Renovate](https://github.com/renovatebot/renovate) watches the repo for dependency updates — container image digests in compose files and the SOPS version in `dccd.sh`. When updates are found, a PR is automatically created.

---

## 📁 Structure

```sh
📁 truenas-apps
├── 📁 scripts        # CD script (dccd.sh)
└── 📁 src            # App stacks
    ├── 📁 echo-server
    ├── 📁 gatus
    ├── 📁 homepage
    ├── 📁 immich
    ├── 📁 plex
    ├── 📁 traefik
    └── 📁 shared     # Shared env files (TZ, PUID/PGID)
```

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
