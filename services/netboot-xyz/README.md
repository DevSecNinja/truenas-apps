# netboot.xyz

netboot.xyz is a network boot manager that serves PXE menus and OS installers over TFTP, letting you install or recover operating systems on bare-metal machines without a USB stick.

## Why

Maintaining a collection of USB boot drives for different installers is error-prone and slow to update. netboot.xyz replaces all of them with a single TFTP server: any machine on the network that supports PXE (BIOS or UEFI) can boot into a live menu containing hundreds of up-to-date OS installers, rescue environments, and utilities. The web UI makes it easy to customise boot menus and add locally-hosted assets (ISO images, kernel files) for air-gapped installs.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/netboot-xyz/compose.yaml)

## Access

| URL                              | Protocol | Description                            |
| -------------------------------- | -------- | -------------------------------------- |
| `https://netboot.${DOMAINNAME}`  | HTTPS    | Web admin UI (Traefik forward-auth)    |
| Host port `69/udp`               | TFTP     | PXE boot — not proxied through Traefik |

## Architecture

- **Image**: [linuxserver/netbootxyz](https://github.com/linuxserver/docker-netbootxyz) (s6-overlay)
- **User/Group**: `PUID=3125` / `PGID=3125` (`svc-app-netboot`)
- **Networks**: `netboot-xyz-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware; web UI served on internal port `3000`

### Ports

| Port | Protocol | Purpose                                                            |
| ---- | -------- | ------------------------------------------------------------------ |
| 69   | UDP      | TFTP — required for PXE booting; cannot be proxied through Traefik |

### s6-overlay Exceptions

This container uses LinuxServer's s6-overlay init system, which requires deviations from the standard hardening baseline (see [Architecture](../ARCHITECTURE.md)):

- **`read_only` is omitted**: s6-overlay writes `/etc/passwd` and `/etc/group` to apply `PUID`/`PGID` at startup; these writes fail silently with `read_only: true`, causing `PUID`/`PGID` to be ignored entirely.
- **`user:` is omitted**: s6-overlay starts as root and handles the privilege drop to `PUID:PGID` internally.
- **No external init container**: s6-overlay chowns `/config` and `/assets` to `PUID:PGID` at startup, so no separate `netboot-xyz-init` service is needed.
- **`cap_drop: ALL` is still applied**; only the capabilities s6-overlay needs are re-added:

| Capability | Reason                                                                        |
| ---------- | ----------------------------------------------------------------------------- |
| `CHOWN`    | s6-overlay chowns `/config` and `/assets` to `PUID:PGID` at startup          |
| `SETUID`   | s6-overlay drops from root UID to `PUID`                                      |
| `SETGID`   | s6-overlay drops from root GID to `PGID`                                      |
| `SETPCAP`  | s6-overlay clears the bounding capability set before exec-ing the application |

### Volumes

| Container Path | Host Path       | Mode | Purpose                                           |
| -------------- | --------------- | ---- | ------------------------------------------------- |
| `/config`      | `./data/config` | rw   | Persistent configuration (boot menus, settings)  |
| `/assets`      | `./data/assets` | rw   | Optional custom assets (ISO images, kernel files) |

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/netboot-xyz` in TrueNAS
2. Create a `svc-app-netboot` group (GID 3125) and user (UID 3125) on the TrueNAS host — create the group first to guarantee UID = GID (see [Infrastructure](../INFRASTRUCTURE.md#truenas-host-setup))
3. Configure your DHCP server to send PXE boot options:
    - **Next-server**: IP address of the TrueNAS host (`${IP_SVLNAS}`)
    - **Filename** (BIOS): `netboot.xyz.kpxe`
    - **Filename** (UEFI): `netboot.xyz.efi`
4. Deploy the stack — s6-overlay initialises `/config` and `/assets` on first start
5. Open `https://netboot.${DOMAINNAME}` to access the web UI — OS installers are available immediately from the default boot menus

<!-- dprint-ignore -->
!!! tip "UEFI vs BIOS filename"
    Some DHCP servers (e.g. OPNsense) support sending different filenames based on client architecture. Set `netboot.xyz.kpxe` for BIOS clients (arch `00:00`) and `netboot.xyz.efi` for UEFI clients (arch `00:07` / `00:09`).

## Upgrade Notes

No special upgrade procedures. s6-overlay handles config migration on startup. Image updates are managed by Renovate.
