# Plex

Plex is a self-hosted media server that organizes and streams your personal video, music, and photo libraries to any device.

## Why

Streaming services fragment your library across subscriptions and can remove content at any time. Plex lets you serve your own media collection to any device — phones, TVs, browsers — with a polished interface, hardware-accelerated transcoding, and offline sync. Running it behind Traefik means remote access works through your existing reverse proxy without exposing additional ports.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/plex/compose.yaml)

## Access

| URL                          | Description                      |
| ---------------------------- | -------------------------------- |
| `https://plex.${DOMAINNAME}` | Web UI (proxied through Traefik) |

## Architecture

- **Image**: [linuxserver/plex](https://github.com/linuxserver/docker-plex) (s6-overlay)
- **Reverse proxy**: Traefik with `chain-no-auth-plex` middleware — no forward-auth because Plex has its own authentication; uses a relaxed CSP to allow plex.tv/plex.direct. The Traefik backend uses `insecure-skip-verify` server transport because Plex serves HTTPS on port 32400 with a self-signed certificate — TLS is still enforced end-to-end between the client and Traefik.
- **Hardware transcoding**: Intel GPU via `/dev/dri/renderD128`
- **Transcode temp dir**: `/dev/shm` (RAM-backed) — must also be set in Plex settings as `/data/transcode`
- **Media mount**: `/mnt/archive-pool/content/media` → `/media` (read-only)
- **User/Group**: `911:3200` (LinuxServer default UID / media GID)
- **pids_limit**: `500` — Plex spawns many threads for plugins, database, and transcoding

### s6-overlay Exceptions

This container uses LinuxServer's s6-overlay init system, which requires deviations from the standard hardening baseline (see [Architecture](../ARCHITECTURE.md)):

- **`read_only` is omitted**: s6-overlay writes `/etc/passwd` and `/etc/group` to apply PUID/PGID at startup; these writes fail silently with `read_only: true`, causing PUID/PGID to be ignored entirely.
- **`user:` is omitted**: s6-overlay starts as root and handles the privilege drop to PUID:PGID internally.
- **`/run` is mounted as tmpfs with `exec`**: s6-overlay stores its service files here and needs to execute them.
- **`cap_drop: ALL` is still applied**; only the capabilities s6-overlay needs are re-added:

  | Capability     | Reason                                                                                                                  |
  | -------------- | ----------------------------------------------------------------------------------------------------------------------- |
  | `CHOWN`        | s6-overlay chowns `/config` to PUID:PGID at startup                                                                     |
  | `DAC_OVERRIDE` | s6-overlay runs as root before dropping privileges; needed to write into `/config` even when already owned by PUID:PGID |
  | `KILL`         | `init-plex-claim` (root) signals the temporary Plex process (UID 911) during server claiming                            |
  | `SETGID`       | s6-overlay drops from root GID to PGID                                                                                  |
  | `SETUID`       | s6-overlay drops from root UID to PUID                                                                                  |
  | `SETPCAP`      | s6-overlay clears the bounding capability set before exec-ing Plex                                                      |

### Init Container

The `plex-init` service pre-sets ownership on `./data/config` and `./backups` to `911:3200` before Plex starts. This is a belt-and-suspenders measure for fresh deploys or ACL resets on ZFS — the main guard is `DAC_OVERRIDE` on the Plex container itself.

## First-Run Setup

1. Get a [Plex claim token](https://www.plex.tv/claim/) (valid for 4 minutes only) and set it in `secret.sops.env`
2. Deploy the stack
3. In **Settings → Network**:
   - Set **Custom server access URLs** to `https://plex.<DOMAINNAME>:443`
   - Set **LAN Networks** to `192.168.0.0/16,172.16.0.0/16`
     (the `172.16.0.0/16` range covers Traefik's Docker bridge network so proxied connections are treated as local)
   - Disable **Enable Relay** to prevent streams from being routed through Plex's external relay servers
4. In **Settings → Remote Access**:
   - Enable **Remote Access** — this is required so Plex publishes your custom access URL to plex.tv for client discovery
   - Select **Manually specify public port** and set it to `443` (Traefik's HTTPS port)
   - The dashboard may show remote access as unavailable (red) — this is expected since port 32400 is not publicly exposed
   - The server settings page may still show connections as "Remote" — this is normal; actual stream status (Local/Direct) is visible in the dashboard activity view
5. In **Settings → Library**: enable automatic library scanning
6. In **Settings → Scheduled Tasks**: set backup directory to `/backups`

## Networking Notes

All client connections flow through Traefik (`phone → Traefik:443 → Plex:32400`). There is no meaningful latency or quality impact from the proxy — Traefik forwards HTTP streams without re-encoding.

Plex sees Traefik's Docker bridge IP as the client source. Without `172.16.0.0/16` in **LAN Networks**, Plex treats these connections as remote, which can cause relay fallback ("Indirect" streams) or bandwidth throttling.

The relay feature (disabled above) routes streams through Plex's internet servers when direct connection fails. While it requires plex.tv authentication, it does expose media traffic outside the local network.

## Volumes

| Container Path    | Host Path                         | Mode | Purpose                         |
| ----------------- | --------------------------------- | ---- | ------------------------------- |
| `/config`         | `./data/config`                   | rw   | Plex configuration and database |
| `/data/transcode` | `/dev/shm`                        | rw   | Transcode temp (RAM-backed)     |
| `/backups`        | `./backups`                       | rw   | Scheduled backup output         |
| `/media`          | `/mnt/archive-pool/content/media` | ro   | Media library                   |

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `PLEX_CLAIM_TOKEN` — one-time claim token for server registration

## Upgrade Notes

No special upgrade procedures. Plex handles database migrations automatically on startup. The claim token is only needed for initial setup — it can be removed from `secret.sops.env` after the server is registered. Image updates are managed by Renovate.
