# Infrastructure

This page covers host-level setup, identity allocation, storage configuration, and multi-server deployment — everything outside the Docker Compose files themselves. For compose patterns and container security rules, see [Architecture](ARCHITECTURE.md).

## Hardware (svlnas)

The primary TrueNAS server is a compact, passively-cooled build optimised for low noise and low power consumption.

| Category    | Qty | Component                       | Notes                              |
| ----------- | --- | ------------------------------- | ---------------------------------- |
| CPU         | 1   | Intel Core i3-9100              | 4C/4T, 65 W TDP, UHD Graphics 630  |
| Motherboard | 1   | Fujitsu D3644-B                 | LGA 1151, supports ECC UDIMMs      |
| Memory      | 2   | Kingston KSM26ED8/32MF (32 GB)  | DDR4-2666 ECC UDIMM — 64 GB total  |
| Boot SSD    | 1   | Crucial M4 128 GB               | SATA 2.5″ — TrueNAS OS boot drive  |
| Apps SSD    | 1   | Samsung 970 Evo Plus 2 TB       | NVMe M.2 — apps pool (vm-pool)     |
| Data HDDs   | 2   | Seagate IronWolf 4 TB           | CMR, 5900 RPM — ZFS mirror pool    |
| Case        | 1   | Fractal Design Core 1000        | Micro-ATX tower, USB 3.0 front I/O |
| CPU Cooler  | 1   | Arctic Alpine 12 Passive        | Fanless — zero noise from CPU      |
| Case Fan    | 1   | Noctua NF-A9 PWM (92 mm)        |                                    |
| Case Fan    | 1   | Scythe Slip Stream PWM (120 mm) |                                    |
| PSU         | 1   | Mini-box PicoPSU-160-XT         | DC-DC picoPSU — very low idle draw |
| Accessory   | 1   | Mini-box PCI Bracket            | Mounts picoPSU connector to case   |

## Host Boot-Time Setup

TrueNAS SCALE resets host-level configuration (sysctl values, NIC settings, `/etc/avahi`, Incus network config) on system updates and reboots. Any host tweak required by the containerized services must therefore be re-applied at **every boot**.

All of these tweaks are consolidated into a single script, `scripts/host-init.sh`, registered as a TrueNAS **Post Init** Init/Shutdown script. It runs as root, and each block is idempotent — it checks the current state and skips work that is already applied. This single script replaces three previously separate Post Init entries (two `ethtool` commands and the standalone `host-sysctl.sh` entry).

### Init/Shutdown Scripts Configuration

Register the script in the TrueNAS GUI under **System Settings → Advanced → Init/Shutdown Scripts**:

| Setting | Value                                             |
| ------- | ------------------------------------------------- |
| Type    | Command                                           |
| Command | `bash /home/truenas_admin/host-init/host-init.sh` |
| When    | Post Init                                         |
| Enabled | Yes                                               |

Use **Type: Command**, not **Type: Script**. The Script file picker only browses paths under `/mnt`, so it cannot select the `/home` mirror; Command is a free-text field with no path restriction.

The command points at an **unencrypted mirror** of the script, not the repo copy on the encrypted apps pool — see [Why the script lives on unencrypted storage](#why-the-script-lives-on-unencrypted-storage) below.

After adding this entry, delete the three legacy Post Init entries it replaces (the two `ethtool` offload commands and the `host-sysctl.sh` script). Also delete any earlier entry that pointed at the encrypted-pool path `bash /mnt/vm-pool/apps/scripts/host-init.sh` — that path silently no-ops at boot because the dataset is still locked.

To apply the changes without a reboot, run the script by hand once: `sudo bash /mnt/vm-pool/apps/scripts/host-init.sh`.

### Why the script lives on unencrypted storage

The repository lives on an **encrypted ZFS dataset** at `/mnt/vm-pool/apps`, which is unlocked **manually after every boot**. When TrueNAS runs its Post Init scripts, that dataset is still locked, so `/mnt/vm-pool/apps/scripts/host-init.sh` does not yet exist — which is why pointing the Post Init entry at the repo copy never ran anything at boot.

To fix this, `scripts/dccd.sh` mirrors the script to an **unencrypted, always-mounted** boot-pool path that is available immediately at boot:

| Property        | Value                                                                                      |
| --------------- | ------------------------------------------------------------------------------------------ |
| Function        | `sync_host_init()` in `scripts/dccd.sh`                                                    |
| Destination     | `/home/truenas_admin/host-init/` (override via `HOST_INIT_SYNC_DEST`)                      |
| Files mirrored  | `host-init.sh` → `host-init/host-init.sh`, `lib/log.sh` → `host-init/lib/log.sh`           |
| When it runs    | Every TrueNAS-mode (`-t`) dccd run, immediately after `update_compose_files()`             |
| Update strategy | Overwrites the destination unconditionally on every run (no change tracking — kept simple) |
| Privileges      | Plain `cp` (no `sudo`) into the user-owned `/home/truenas_admin` path                      |

The `lib/log.sh` dependency is preserved under `host-init/lib/log.sh` so the relative `source` inside `host-init.sh` still resolves. The copy runs **without `sudo`**, writing only to the user-owned `/home/truenas_admin` path, so it stays safe to run from a passwordless cron job. The destination can be changed by setting `HOST_INIT_SYNC_DEST` (default `/home/truenas_admin/host-init`); the Post Init command must then point at `<HOST_INIT_SYNC_DEST>/host-init.sh` to match.

<!-- dprint-ignore -->
!!! note "First-run bootstrap"
    The mirror only appears after at least one TrueNAS-mode dccd run completes following an unlock. For the very first setup, run dccd manually once after unlocking the dataset (or copy `host-init.sh` and `lib/log.sh` by hand) before relying on the boot hook.

### What the Script Does

`scripts/host-init.sh` performs four independent, idempotent blocks:

| Block                  | Action                                                                                                                                     | Why                                                                                                                                                            |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Intel NIC offload      | Runs `ethtool -K <nic> tso off gso off` on `enp0s31f6` and `eno1` (only if present)                                                        | The Intel I219 (`e1000e` driver) periodically resets under load with "Detected Hardware Unit Hang" unless segmentation offload is off                          |
| Host sysctl tuning     | Sets `net.ipv4.igmp_max_memberships=256`                                                                                                   | The default of 20 is too low for matter-server's Zeroconf multicast joins (see below)                                                                          |
| Avahi mDNS coexistence | Sets `disallow-other-stacks=no` in `/etc/avahi/avahi-daemon.conf`, removes a redundant `deny-interfaces` line, and restarts `avahi-daemon` | Lets the matter-server container share mDNS UDP port 5353 with the host's Avahi, and prevents an overflow-prone interface list from breaking Avahi (see below) |
| Incus dnsmasq port     | Runs `incus network set incusbr0 raw.dnsmasq="port=5354"`                                                                                  | Moves the `incusbr0` bridge's dnsmasq off port 5353 so it never contends with matter-server's mDNS responder                                                   |

### Host sysctl Tuning (`igmp_max_memberships`)

The matter-server service uses Zeroconf (mDNS) for device discovery, which tries to join a multicast group on every interface. The default `net.ipv4.igmp_max_memberships` of 20 is too low and the join fails with:

```text
OSError: [Errno 105] No buffer space available
```

`host-init.sh` raises the limit to 256.

### Avahi mDNS Coexistence (port 5353)

The matter-server container runs with `network_mode: host` and binds its own CHIP mDNS responder to UDP port 5353. The host's `avahi-daemon` already owns 5353 with an **exclusive** lock, so after a reboot the container fails to start with:

```text
chip.exceptions.ChipStackError: ... OS Error 0x02000062: Address already in use
```

Setting `disallow-other-stacks=no` in `/etc/avahi/avahi-daemon.conf` lifts Avahi's exclusivity lock (enables `SO_REUSEPORT`) so both mDNS responders coexist on port 5353. Avahi keeps full functionality — `.local` hostname resolution and SMB/SSH/printer discovery all continue to work. Avahi and the CHIP stack advertise different service types (Avahi: host/SSH/SMB records; CHIP: `_matter`/`_matterc` commissioning records), so record collisions are not a practical concern.

The Incus dnsmasq block exists for the same reason: it moves a second 5353 listener (the `incusbr0` bridge's dnsmasq) onto port 5354 so only Avahi and CHIP share 5353.

The block also removes a `deny-interfaces` line from the Avahi config whenever an `allow-interfaces` line is present. Avahi ignores `deny-interfaces` entirely once `allow-interfaces` is set, and TrueNAS auto-populates `deny-interfaces` with every Docker bridge (`br-*`). That list grows unbounded as containers come and go and eventually overflows Avahi's per-line config parse buffer, causing the daemon to fail at startup with `Missing assignment ... <r-...>`. Dropping the redundant line is behaviour-neutral (the allow-list still governs which interfaces Avahi binds) and prevents the overflow from recurring. The block backs up the config before editing and verifies the restart — if `avahi-daemon` fails to come back up, the original config is restored so the host is never left without a working responder.

## UID/GID Allocation

Every service runs under a dedicated non-root user with a unique UID. Each user has an auto-created primary group with the same GID (UID = GID). This ensures file ownership is unambiguous in `ls -la` and allows fine-grained access control via TrueNAS group membership.

### Naming Convention

TrueNAS service accounts follow the pattern `svc-app-<name>` (e.g., `svc-app-traefik`). This distinguishes them from human users and makes their purpose immediately clear in `ls -la` output.

### VM and Host Naming Convention

All servers and workstations follow a structured naming scheme:

```
<type><os>[az]<description>
```

| Segment         | Values          | Meaning                                          |
| --------------- | --------------- | ------------------------------------------------ |
| `<type>`        | `sv`            | Server                                           |
|                 | `ws`            | Workstation                                      |
| `<os>`          | `l`             | Linux                                            |
|                 | `w`             | Windows                                          |
| `[az]`          | `az` (optional) | Running in Azure; omit for on-premises           |
| `<description>` | short noun      | What the machine does (e.g. `nas`, `dev`, `ext`) |

**Examples:**

| Name       | Meaning                                       |
| ---------- | --------------------------------------------- |
| `svlnas`   | Server · Linux · NAS (the TrueNAS host)       |
| `svlazdev` | Server · Linux · Azure · development VM       |
| `svlazext` | Server · Linux · Azure · external-facing      |
| `wsldev`   | Workstation · Linux · development workstation |

### ID Ranges

| Range     | Purpose                                          |
| --------- | ------------------------------------------------ |
| 911       | Reserved for Plex (LinuxServer image default)    |
| 3100–3199 | Per-app service accounts (UID = GID)             |
| 3200+     | Shared purpose groups (no matching user account) |

Each service account has a matching `svc-app-<name>` group created at the same GID as its UID. These groups are **GID reservations only** — they exist to prevent TrueNAS from assigning the GID to an unrelated group in the future. The app's _functional_ primary group is typically a shared purpose group (e.g., `media` at GID 3200), not the `svc-app-*` placeholder. There is generally no need to add `truenas_admin` or other users to the `svc-app-*` groups. Dawarich is an exception: `truenas_admin` belongs to `svc-app-dawarich` for operational access to its mode `770` runtime directories.

### App Service Accounts

| UID/GID | TrueNAS user              | Service(s)                                                                          | Git-tracked config?  |
| ------- | ------------------------- | ----------------------------------------------------------------------------------- | -------------------- |
| 3101    | `svc-app-adguard`         | adguard, adguard-init, adguard-unbound-init                                         | No (`./data/conf`)   |
| 3125    | `svc-app-alloy`           | alloy, alloy-init                                                                   | Yes (`./config`)     |
| 3126    | `svc-app-bitwarden`       | bitwarden                                                                           | No                   |
| 3131    | `svc-app-changedetection` | changedetection; changedetection-init ownership target                              | No (`./data`)        |
| 3128    | `svc-app-dawarich`        | dawarich, dawarich-sidekiq, dawarich-init, dawarich-db-backup                       | No                   |
| 3109    | `svc-app-dozzle`          | dozzle, dozzle-init                                                                 | No                   |
| 3119    | `svc-app-drawio`          | drawio                                                                              | No                   |
| 3104    | `svc-app-echo`            | echo-server                                                                         | No                   |
| 3103    | `svc-app-gatus`           | gatus, gatus-db-backup                                                              | No                   |
| 3102    | `svc-app-homepage`        | homepage, homepage-init                                                             | Yes (`./config`)     |
| 3106    | `svc-app-immich`          | immich-server, immich-ml, immich-init                                               | No                   |
| 3130    | `svc-app-karakeep`        | karakeep, karakeep-workers, karakeep-meilisearch, karakeep-init, karakeep-db-backup | No                   |
| 3124    | `svc-app-matter`          | matter-server, matter-server-init                                                   | No                   |
| 3129    | `svc-app-memos`           | memos, memos-init                                                                   | No                   |
| 3107    | `svc-app-metube`          | metube, metube-init                                                                 | No                   |
| 3122    | `svc-app-mosquitto`       | mosquitto, mosquitto-init                                                           | Yes (`./config`)     |
| 3127    | `svc-app-openclaw`        | openclaw, openclaw-init                                                             | No                   |
| 3120    | `svc-app-outline`         | outline-db-backup†                                                                  | No                   |
| 3113    | `svc-app-prowlarr`        | prowlarr                                                                            | No (`./data/config`) |
| 3110    | `svc-app-radarr`          | radarr                                                                              | No                   |
| 3117    | `svc-app-spottarr`        | spottarr; spottarr-chown ownership target                                           | No (`./data`)        |
| 3100    | `svc-app-traefik`         | traefik, traefik-init                                                               | Yes (`./config`)     |
| 3105    | `svc-app-tfa`             | traefik-forward-auth, init                                                          | No (`./data`)        |
| 3118    | `svc-app-tubesync`        | tubesync                                                                            | No                   |
| 3108    | `svc-app-unifi`           | unifi, unifi-db-backup                                                              | No                   |
| 3123    | `svc-app-wmbusmeters`     | wmbusmeters, wmbusmeters-init                                                       | Yes (`./config`)     |

† The `outlinewiki/outline` image does not support PUID/PGID — it runs as the
image-internal `node` user, explicitly selected by `user: "1000:1000"`.
The registry's `svc-app-outline` account has UID and primary GID `3120`,
used by `outline-db-backup` through `USER_DBBACKUP` and `GROUP_DBBACKUP`.
It does not replace the main application's image-internal identity:
`outline-init` still uses `docker.io/library/busybox:1.38.0` to chown
`./data/data` to `1000:1000`. See:
https://github.com/outline/outline/discussions/9452

Prowlarr and Spottarr use their listed UID as the matching primary GID, with
no shared-purpose group memberships. Prowlarr selects the dedicated account
through `PUID`/`PGID`; Spottarr uses `user:`. Its `spottarr-chown` init runs
`docker.io/library/busybox:1.38.0` as root and assigns `./data` ownership to
the app's `3117:3117` identity.

The `svc-app-changedetection` account has UID `3131`, primary group
`svc-app-changedetection` (GID `3131`), and no shared-purpose group memberships.
The app uses this identity; `changedetection-init` runs as root and assigns
the datastore to it. Registry key `changedetection` sets
`admin_group_member=false`, so the helper does not add the administrator to
the service group. `changedetection-chrome` uses DHI's `65532:65532`;
its browser proxy uses `65534:65534`.
Neither uses the TrueNAS app allocation.

The `svc-app-dawarich` user has UID 3128, primary group
`svc-app-dawarich` (GID 3128), and no shared-purpose group memberships.
The application, worker, init ownership target, and database backup sidecar
use this identity. The nfrastack/db-backup `4.9.2` compatibility release selects
it through `USER_DBBACKUP=3128` and `GROUP_DBBACKUP=3128`.

The `svc-app-memos` user has UID 3129, primary group `svc-app-memos` (GID
3129), and no shared-purpose group memberships. The Memos application and init
container use this identity.

The `svc-app-karakeep` account has matching UID and primary GID `3130` and no
shared-purpose group memberships. The web, worker, and Meilisearch processes
use this identity; `karakeep-init` assigns their runtime paths and the database
backup output child to it. The `karakeep-db-backup` s6 supervisor starts as
root, then maps `USER_DBBACKUP` and `GROUP_DBBACKUP` to `3130` so the backup
process uses this identity. `karakeep-chrome` uses DHI's `65532:65532`,
while its proxy uses `65534:65534`.
Neither needs a new TrueNAS account or shared-group membership.

### Stateless Browser Proxies

changedetection.io and Karakeep each use a dedicated Canonical Squid
`7.2-26.04_edge` proxy using the same approved digest and shared read-only
`services/shared/config/browser/squid.conf`. Both browser and proxy services
are active by default in Compose, without profiles. Neither proxy needs a
dataset, host service account, ownership init, new secret, or database backup.
Each uses only `/tmp` scratch, a read-only root filesystem, dropped
capabilities, `${BROWSER_PROXY_MEM_LIMIT:-256m}`, and a 100-PID limit.

Only each proxy joins its app's browser-egress bridge. Chrome is attached
only to the internal browser network, which it shares with app clients and
the proxy. There are no host-published proxy ports or new host firewall or
dependency requirements. Internal-site crawling/monitoring is intentionally
unsupported by the [public-website-only policy](ARCHITECTURE.md#browser-egress-policy-public-websites-only);
do not add direct fallbacks, bypass rules, or Chrome egress networks.
Non-browser Basic HTTP app traffic is not filtered through this proxy.

The DHI browser mounts `services/shared/config/browser/launch.mjs`
read-only. The minimum `153.0.8010.52` is mandatory: neither browser definition
sets `BROWSER_ALLOW_UNPATCHED_VERSION`, so older cached `153.0.8010.47`
images fail closed. A fresh pull of the unchanged DHI tag
reported Chromium `153.0.8010.52` from the actual binary on a disposable
rootful Podman VM; see the
[verified image references](ARCHITECTURE.md#browser-egress-policy-public-websites-only).
Both services watch the
shared `browser` directory for config changes. Initial DHI adoption is
tag-only, with Renovate digest pinning to follow; no custom image publication
or new persistent storage is required.

Normal deployment recreates changed browser definitions; no profile-related
shutdown is required for this transition. For existing apps, use the sourced
aliases to run `dccd-app karakeep`, `dccd-app changedetection`, then
`dccd-all`. Verify both browsers meet the version floor without an exception
warning and that service health and browser workflows pass.
See [Browser Runtime Validation](ARCHITECTURE.md#browser-runtime-validation)
for historical synthetic checks on the older image and remaining checks.
The new binary-version verification is not a production deployment or a
full application/proxy revalidation.

**Test runtime:** use rootful Podman on the test VM. The Canonical image
contains layer file ownership outside that VM's default rootless subordinate
UID range, preventing unpack there; this is distinct from the configured
runtime identity. The target TrueNAS runtime is rootful Docker. The proxy's
effective runtime UID remains the explicitly configured non-root identity,
which worked in the proxy test. No host UID-range or dependency change is
required by this deployment.

### Shared Purpose Groups

These groups have no matching user account. They grant cross-service access to shared datasets.

changedetection.io uses only its dedicated primary group; it requires no
membership in the shared groups below.

| GID  | Group               | Purpose                                      | Used as primary group by                                                                                                                                                       |
| ---- | ------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 3200 | `media`             | Read/write access to media datasets          | Plex (UID 911), MeTube (UID 3107), Radarr (UID 3110), Bazarr (UID 3111), Lidarr (UID 3112), qBittorrent (UID 3114), SABnzbd (UID 3115), Sonarr (UID 3116), TubeSync (UID 3118) |
| 3202 | `private-photos`    | Access to private photos (Immich upload dir) | Immich (UID 3106)                                                                                                                                                              |
| 3203 | `private-documents` | Access to private documents (reserved)       | —                                                                                                                                                                              |

### Plex Exception

Plex stays at UID 911 (LinuxServer image default) with PGID 3200 (`media`). The s6-overlay init system manages permissions internally. UID 911 is reserved exclusively for Plex — no other service may use it. For naming consistency, create a `svc-app-plex` user on TrueNAS with UID 911 and primary group `media` (GID 3200).

### TrueNAS Host Setup

For apps supported by `scripts/truenas-prep-app.sh`, run the reusable
preparation command from the repository root instead of manually creating the
app identity and child dataset. The root `truenas-apps.json` provisioning
registry is the declarative source for supported apps. Each `apps.<name>` entry
defines the dedicated account name, shared UID/GID, and whether the
administrative user needs auxiliary app-group membership.
`truenas-apps.schema.json`, CI, and Lefthook validate the registry fields and
service directory references. The helper requires `jq` on `PATH` to read the
JSON registry and construct TrueNAS API payloads.

#### Registry Coverage

The registry currently enrolls **19 app stacks** using the existing dedicated
account model: `adguard`, `alloy`, `bitwarden`, `changedetection`, `dawarich`,
`dozzle`, `drawio`, `gatus`, `homepage`, `karakeep`, `memos`, `mosquitto`,
`openclaw`, `outline`, `prowlarr`, `spottarr`, `traefik`, `unifi`, and
`wmbusmeters`.

Each uses the exact `svc-app-<key>` account/group name and a matching UID and
primary GID from the registry. `admin_group_member` is `false` for every
enrolled app except Dawarich, whose existing administrative-access requirement
remains enabled. Enrollment does not change Compose runtime identities or
make every container use the host account.

A registry key identifies an app stack under `services/`, not an individual
init, browser, database, or backup container. Outline is enrolled because its
dedicated host account is used by the backup sidecar; the main application's
image-internal identity remains managed separately as described above.

Advanced provisioning remains deferred to
[issue #772](https://github.com/DevSecNinja/truenas-apps/issues/772):

- Legacy account-name aliases: `echo-server`, `matter-server`, and
  `traefik-forward-auth`.
- Shared media/photo primary groups and [Plex's fixed identity](#plex-exception).
- Apps requiring no host account or dataset-only provisioning.

Do not treat these deferred cases as helper-supported or allocate replacement
identities to force them into the current model. The registry and the helper's
generated usage output remain the authoritative supported-key list.

#### TrueNAS Script Dependency Policy

Scripts executed directly on TrueNAS must minimize external dependencies:

- Verify each new command or library against the actual TrueNAS baseline or a
  documented provisioning path before using it.
- Prefer shell built-ins and existing dependencies. The provisioning helper
  reuses `jq` for the JSON registry rather than adding `yq`.
- Python may be used when appropriate after verifying its interpreter and
  required libraries against the host baseline. Its standard library does not
  parse YAML; JSON plus the existing `jq` dependency lets this helper avoid
  PyYAML or another package.
- Do not assume tools installed by `mise` for development or CI are available
  at TrueNAS runtime.
- For an unavoidable dependency, add an explicit availability check, document
  its installation or provisioning path, and validate it on the TrueNAS host.
  Redesign the implementation if those conditions cannot be met.
- Test behavior without optional or non-guaranteed commands when relevant.

The `yq` requirement in [Multi-Server Deployment](#multi-server-deployment)
applies only to explicitly provisioned non-TrueNAS server mode.

#### Brand-New Custom App Rollout

Use this sequence after merging a new registry-supported app. On `svlnas`, the
aliases must already be sourced from `/mnt/vm-pool/apps/scripts/aliases.sh`.

1. Pull the merged changes and decrypt SOPS files while limiting the first pass
   to the new app:

   ```sh
   dccd-app <app>
   ```

   Because the TrueNAS Custom App does not exist yet, dccd reports that its
   TrueNAS app config directory is missing and skips deployment. This is
   expected during the first pass. Do not run `dccd-all` first: Traefik may
   already reference the new frontend network before its Custom App and network
   exist.
2. From the updated checkout, provision the registry-declared account, group,
   and child dataset:

   ```sh
   cd /mnt/vm-pool/apps
   sudo bash scripts/truenas-prep-app.sh <app>
   ```

   The helper preserves the files already checked out under the service
   directory.
3. In the TrueNAS UI, create a Custom App named `<app>` with:

   ```yaml
   include:
     - /mnt/vm-pool/apps/services/<app>/compose.yaml
   services: {}
   ```

4. Run the canonical final deployment:

   ```sh
   dccd-all
   ```

   This force-deploys all TrueNAS apps in the normal order, includes the new
   app and dependent AdGuard and Traefik changes, decrypts secrets, and runs the
   default backup freshness check.
5. Complete the application-specific first-run setup and verify health and
   access.

Do not replace this handoff with raw `git pull`, raw `dccd.sh` invocations, or
an improvised series of targeted app deployments unless troubleshooting or
explicitly requested.

The helper reads the selected registry entry and creates or verifies the app
group and user using the allocation in the
[App Service Accounts](#app-service-accounts) table. It adds the administrative
user to the app group only when requested, creates the app child dataset beneath
the ZFS dataset mounted at `services/`, and sets the app directory to the
administrative owner with mode `0770`. If the service directory already
contains the checkout, the command stages and restores those files around
dataset creation. Repeated runs are safe: existing matching resources are
reused, while account name or ID collisions stop the operation. It also refuses
to create a missing dataset while the app is running. The helper's usage output
lists the current registry keys. Set `TRUENAS_ADMIN_USER` only when the local
administrative account is not `truenas_admin`.

The `services/` parent must already be a mounted ZFS dataset. Use the manual
creation procedure below only for justified apps that cannot use the helper.

**Important:** When creating service accounts in TrueNAS, always **create the group first**, then the user. If you rely on TrueNAS's "auto-create primary group" checkbox when creating a user, TrueNAS assigns the earliest available GID — which may not match the desired UID. By pre-creating the group with the correct GID, the auto-created primary group step is skipped and UID = GID is guaranteed.

Creation order for each app service account:

1. Create group `svc-app-<name>` with GID matching the UID (e.g., GID 3100) — this is a GID reservation to prevent conflicts
2. Create user `svc-app-<name>` with UID matching the GID (e.g., UID 3100), primary group set to the app's functional group (e.g., `media` for media apps, or the `svc-app-*` placeholder for apps that don't need shared access)
3. For apps with git-tracked config (`./config`): add `truenas_admin` to the app's functional primary group — this grants group-write access to chown'd config files, allowing `git pull` without permission conflicts

For shared purpose groups (`media`, `private-photos`, `private-documents`):

1. Create the groups with the designated GIDs (3200, 3202, 3203).
2. Configure the relevant service accounts' group memberships:
   - `svc-app-plex` (911): primary group `media` (3200)
   - `svc-app-metube` (3107): primary group `media` (3200)
   - `svc-app-immich` (3106): primary group `private-photos` (3202)
3. Add `truenas_admin` as an auxiliary group member of each group if admin access to those datasets is needed

### apps Dataset ACLs

The git repo lives on the `vm-pool/apps` dataset. Because `dccd.sh` decrypts `secret.sops.env` → `.env` files into this tree, access must be restricted to prevent other users from reading secrets.

Create the `vm-pool/apps` dataset via the TrueNAS GUI with these properties:

| Setting      | Value | Why                                                                                            |
| ------------ | ----- | ---------------------------------------------------------------------------------------------- |
| Compression  | `lz4` | Low CPU overhead; reduces snapshot size, replication transfer time, and Cloud Sync uploads     |
| Enable Atime | Off   | Prevents a write on every read; no benefit for app data workloads                              |
| ACL Type     | Off   | Plain Unix permissions; NFSv4 adds complexity with no benefit (same as `archive-pool/content`) |

Verify compression is active: `zfs get compression vm-pool/apps` should return `lz4`. For the `archive-pool/content` dataset, `zstd` is configured instead — see [Dataset Layout](#dataset-layout).

**Owner:** `truenas_admin` — allows `git pull` without sudo. Root does not need ownership because it bypasses all permission checks on Linux/ZFS.

**Owning group:** `truenas_admin`.

Configure the following Unix permissions on the `vm-pool/apps` dataset using the TrueNAS **Unix Permissions Editor**:

| Setting | Value                    |
| ------- | ------------------------ |
| User    | `truenas_admin`          |
| Group   | `truenas_admin`          |
| User    | Read ✓ Write ✓ Execute ✓ |
| Group   | Read ✓ Write ✓ Execute ✓ |
| Other   | No permissions           |

Enable both **Apply permissions recursively** and **Apply permissions to child datasets**. Child datasets are created as `root:root` regardless of the parent's permissions, so this must be done after all child datasets exist.

This gives `truenas_admin` full access while blocking all other users from reading decrypted `.env` files containing secrets. Root does not need explicit permissions — it bypasses all permission checks.

**Per-app config directories** are handled separately by init containers, not by dataset-level permissions:

1. Init containers chown `./config` subdirectories to the app's UID:GID with group-write (`775`/`664`)
2. `truenas_admin` (a member of each app's primary group) gets group-write access via POSIX group permissions
3. Next deploy, the init container re-chowns everything (idempotent)

### changedetection.io Dataset

Registry key `changedetection` provisions
`vm-pool/apps/services/changedetection`. Follow the complete
[brand-new Custom App rollout](#brand-new-custom-app-rollout), using:

```sh
cd /mnt/vm-pool/apps
sudo bash scripts/truenas-prep-app.sh changedetection
```

The helper preserves the checked-out files and creates or verifies the
dedicated account and matching primary group without administrative group
membership.

| Path                    | Purpose                                                                                                  |
| ----------------------- | -------------------------------------------------------------------------------------------------------- |
| `./data` → `/datastore` | **Critical mutable file state**: global/watch/tag JSON, `secret.txt`, history snapshots, and screenshots |

There is no SQLite or other formal database, database-backup sidecar, or
encrypted database dump. The complete directory uses the existing vm-pool
snapshot, replication, and encrypted off-site Cloud Sync coverage. Live file
snapshots are not multi-file application-consistent: gracefully stop the app
before a manual consistent snapshot/export, and restore the complete stopped
datastore. See [Restore changedetection.io file state](BACKUP.md#restore-changedetectionio-file-state).

`changedetection-init` chowns only `./data` to the app account and applies
`u=rwX,g=,o=`. Use elevated privileges for recovery rather than broadening
permissions or granting shared-group access.

#### Static Browser Subnet Reservation

| Reservation                | Value                                             |
| -------------------------- | ------------------------------------------------- |
| Internal IPv4-only network | `changedetection-browser`                         |
| Subnet                     | `172.30.100.16/29`                                |
| Dynamic allocation range   | `172.30.100.16/30`                                |
| Chrome static address      | `172.30.100.22`                                   |
| CDP endpoint               | `PLAYWRIGHT_DRIVER_URL=http://172.30.100.22:9222` |

Reserve this subnet against overlap with Docker, LAN, and VPN networks.
Chrome's address is outside the dynamic allocation range. If relocating the
subnet, update IPAM, Chrome's `ipv4_address`, and `PLAYWRIGHT_DRIVER_URL`
together. The app uses the IP-based HTTP discovery endpoint on each
connection. App, Chrome, and proxy share the control network. Only the proxy joins
`changedetection-browser-egress`. Chrome remains internal-network-only, with
no published ports or frontend membership. See the
[network and access model](ARCHITECTURE.md#changedetectionio-network-and-access-model).

### Dawarich Dataset

Create `vm-pool/apps/services/dawarich` as a child dataset. It contains the
Compose definition and encrypted secrets alongside all Dawarich runtime data:

| Path                  | Purpose                                                                               |
| --------------------- | ------------------------------------------------------------------------------------- |
| `./data/app-tmp`      | Rails application temporary paths, including PID, cache, socket, and home directories |
| `./data/db`           | PostGIS database                                                                      |
| `./data/public`       | Generated public assets                                                               |
| `./data/redis`        | Redis persistence                                                                     |
| `./data/sidekiq-tmp`  | Sidekiq worker cache and home directories                                             |
| `./data/storage`      | Dawarich application storage                                                          |
| `./data/watched`      | Watched GPS import directory                                                          |
| `./backups/db-backup` | ZSTD-compressed, GPG-encrypted PostgreSQL backups with SHA1 sidecars                  |

Before the first deployment:

1. From the repository root on TrueNAS, provision the account, administrative
   group membership, and child dataset:

   ```sh
   sudo bash scripts/truenas-prep-app.sh dawarich
   ```

   The helper ensures that the `svc-app-dawarich` group uses GID 3128, adds
   `truenas_admin` as an auxiliary member for access to mode `770` runtime
   directories, creates the `svc-app-dawarich` user with UID 3128 and that
   primary group, and creates the `vm-pool/apps/services/dawarich` dataset.
2. Manually populate every required value in
   `services/dawarich/secret.sops.env`.

`dawarich-init` assigns the public assets, storage, watched imports, and the
app/worker temporary paths to `3128:3128`. Redis is assigned to its
image-internal `999:999` identity. PostGIS manages its own runtime directory
permissions. The nfrastack/db-backup `4.9.2` compatibility release manages the
backup path while mapping its internal user and group to `3128:3128` through
`USER_DBBACKUP` and `GROUP_DBBACKUP`. The init container retains `CHOWN`,
`FOWNER`, and `DAC_OVERRIDE`; `DAC_OVERRIDE` lets repeat deployments traverse
mode `770` runtime paths. Before changing ownership, it fails if any required
decrypted value is empty or `CHANGE_ME`. PostGIS and Redis depend on successful
init completion, so a placeholder database password cannot initialize PostGIS.

The internal `dawarich-backend` network is owned by `_bootstrap` and referenced
as external by both Alloy and Dawarich. A full `dccd.sh` deployment processes
`_bootstrap` first, so the network exists before either consumer on a fresh
host. Redis and the database backup container remain backend-only. The backup
container sets `ENABLE_NOTIFICATIONS=FALSE` and does not join
`dawarich-frontend`; all remaining `NOTIFICATIONS_EMAIL_*` variables configure
Dawarich application email only.

The backup container runs `backup-now` with `MODE=MANUAL` on every full
`dccd.sh` deployment. It uses ZSTD compression, GPG passphrase encryption
through `DEFAULT_ENCRYPT` and `DEFAULT_ENCRYPT_PASSPHRASE`, a SHA1 sidecar, and
`DEFAULT_CLEANUP_TIME=2880`. Runtime testing successfully decrypted and
restored the dump into a fresh PostgreSQL database. Version 5.0.0 was
intentionally not selected because runtime restore validation failed with an
invalid bigint conversion; `4.9.2` preserves the proven v4 workflow in the
maintained nfrastack image and repository.

### Karakeep Dataset

`vm-pool/apps/services/karakeep` is the child dataset containing the
Compose definition and encrypted secrets alongside Karakeep's persistent data:

| Path                  | Purpose                                                          |
| --------------------- | ---------------------------------------------------------------- |
| `./backups/db-backup` | ZSTD-compressed, GPG-encrypted SQLite backups with SHA1 sidecars |
| `./data/karakeep`     | SQLite database and saved assets                                 |
| `./data/meilisearch`  | Regeneratable Meilisearch full-text search index                 |

Before the first deployment:

1. From the repository root on TrueNAS, provision the account and child
   dataset:

   ```sh
   sudo bash scripts/truenas-prep-app.sh karakeep
   ```

   The helper creates or verifies the `svc-app-karakeep` group with GID 3130,
   the `svc-app-karakeep` user with UID 3130 and that primary group, and the
   `vm-pool/apps/services/karakeep` child dataset. It does not add
   `truenas_admin` to the service group (`ADMIN_GROUP_MEMBER=false`). When
   creating the child dataset, it stages and restores the existing service
   directory. The command is safe to rerun and refuses account identity
   collisions or mismatches.
2. Populate the required Karakeep secrets through SOPS before deploying.

On every deployment, `karakeep-init` creates `./backups/db-backup` through its
`./backups:/backups` parent mount, assigns it and `./data/karakeep` and
`./data/meilisearch` to `3130:3130`, and restricts them to the service account.
The one-shot `karakeep-db-backup` sidecar reads
`./data/karakeep/db.db` read-only. Its s6 supervisor starts as root, then drops
the backup process to `3130:3130` through `USER_DBBACKUP` and
`GROUP_DBBACKUP`. The sidecar mounts the parent `./backups` directory at
`/backup-data` and writes to `/backup-data/db-backup`; this preserves the
pre-owned child when the image resets the read-write mount root to root
ownership, so host output remains exactly `./backups/db-backup`. ZFS snapshots,
replication, and off-site sync protect the full child dataset, including saved
assets and the regeneratable search index that are outside the SQLite backup.

## Media Access

> **Troubleshooting:** If a container cannot read or write media files, see [TROUBLESHOOTING.md § Permissions](TROUBLESHOOTING.md#permissions).

All services that interact with media datasets share a single `media` group (GID 3200). Every media-touching service account on TrueNAS has `media` as its primary group. Unix permissions replace NFSv4 ACLs on these datasets.

**Why not separate reader/writer groups?** Consumer services (e.g., Plex) are already restricted to read-only at the kernel level via `:ro` Docker volume mounts — a filesystem-level write restriction would only be a secondary layer for a modest risk. The same `media` group for all services keeps the model simple, debuggable with plain `ls -la`, and trivially extensible to SMB (add a user to the group, done).

Each media service (e.g., MeTube) runs under its own dedicated UID so file ownership is auditable — `ls -la` shows which service wrote a file.

### Dataset Layout

All media and download data lives under a **single** ZFS dataset `archive-pool/content`, mounted at `/mnt/archive-pool/content/`. No child datasets are created beneath it — everything is plain directories.

**Why one dataset?** Hardlinks only work within the same filesystem. When an arr app (Radarr, Sonarr) imports a finished download, it can create a hardlink from `downloads/` to `media/` instead of copying the file — but only if both paths are on the same ZFS dataset. Child datasets would act as separate filesystems and break this.

```
/mnt/archive-pool/content/
├── downloads/           ← download clients (arr stack)
│   ├── isos/
│   ├── torrents/        ← torrent client (qBittorrent, Deluge, etc.)
│   │   ├── movies/
│   │   ├── music/
│   │   └── tv/
│   └── usenet/          ← Usenet client (SABnzbd, NZBGet, etc.)
│       ├── incomplete/
│       └── complete/
│           ├── movies/
│           ├── music/
│           └── tv/
└── media/               ← final library; Plex reads this
    ├── audiobooks/
    ├── movies/
    ├── music/
    ├── study/
    ├── tv/
    └── youtube/
        └── metube/      ← MeTube writes here
```

All folder names are lowercase — Linux is case-sensitive and lowercase avoids ambiguity.

### TrueNAS Scale Setup

On the TrueNAS host, create or confirm:

- A `media` group (GID 3200) — for all media-touching services
- A `svc-app-plex` user (UID 911) with primary group `media` (GID 3200)
  - UID 911 is fixed by the LinuxServer image; it cannot be changed via `PUID`
  - **UID 911 is reserved exclusively for Plex.** No other service may use this UID unless strictly necessary, and any exception must be documented with a comment in the relevant compose file.
- A dedicated user per media service (e.g., `svc-app-metube` at UID 3107)
  - Primary group: `media` (GID 3200)
  - Use a distinct UID per tool so file ownership is unambiguous in `ls -la`
  - To add a new media service: create its user with primary group `media` — no dataset permission changes needed
- Add `truenas_admin` as an auxiliary group member of `media` for admin access

Create the `archive-pool/content` dataset via the TrueNAS GUI as a **Dataset** (not a zvol) with the following settings:

| Setting      | Value   | Why                                                                                       |
| ------------ | ------- | ----------------------------------------------------------------------------------------- |
| ACL Type     | Off     | Plain Unix permissions; NFSv4 adds complexity with no benefit                             |
| ACL Mode     | Discard | Ensures `chmod` works cleanly without ACL interference                                    |
| Compression  | `zstd`  | Free compression on metadata and small files; video/audio files are already compressed    |
| Enable Atime | Off     | Prevents a write on every read; useless for media workloads                               |
| Exec         | Off     | No binaries run from this path; init containers use their own image layer, not this mount |

Do **not** create child datasets beneath it — everything under `content/` must be plain directories on the same filesystem for hardlinks and atomic moves to work.

The `content-init` container (in the `_bootstrap` service) creates the full directory tree, sets group ownership to `media` (GID 3200), and applies the setgid bit (`2775`) on all directories on every deploy. The `_bootstrap` service deploys first because its directory name sorts before all other services alphabetically. No manual shell setup is needed after the dataset exists.

The **setgid bit** (`2775`) on every directory causes new files and subdirectories to inherit the `media` group automatically. `UMASK=002` in writing services ensures new files are created as `664` (group-readable).

### Container Configuration

All media-touching services hardcode GID 3200 (`media`). Consumer services mount paths `:ro`:

```yaml
environment:
  - PUID=911
  - PGID=3200 # media group — all media-touching services use this GID
volumes:
  - /mnt/archive-pool/content/media/movies:/media/movies:ro
```

Media-writing services omit `:ro` and set `UMASK=002` so created files are group-readable (`664`) and directories group-traversable (`775`):

```yaml
user: "3107:3200" # svc-app-metube:media
environment:
  - UMASK=002
volumes:
  - /mnt/archive-pool/content/media/youtube/metube:/downloads  # read-write; no :ro
```

Future arr apps (Radarr, Sonarr) must mount the entire `/mnt/archive-pool/content/` root so that `downloads/` and `media/` are on the same filesystem inside the container — this is what enables hardlinks and atomic moves:

```yaml
volumes:
  - /mnt/archive-pool/content:/data  # downloads/ and media/ both visible; hardlinks work
```

> **Plex exception:** The LinuxServer Plex image starts as root and drops to `PUID:PGID` via s6-overlay — `read_only: true` breaks this silently, so it is omitted. `user:` is also omitted for the same reason. Despite this, Plex ends up running as 911:3200 matching the dataset group ownership. **UID 911 is reserved for Plex** — no other service may use it unless strictly necessary, and any exception must be documented with a comment in the relevant compose file.

### Service Summary

| Service     | UID               | Primary group  | Media mount | UMASK |
| ----------- | ----------------- | -------------- | ----------- | ----- |
| Plex        | 911 (image-fixed) | 3200 (`media`) | `:ro`       | —     |
| MeTube      | 3107              | 3200 (`media`) | read-write  | `002` |
| Radarr      | 3110              | 3200 (`media`) | read-write  | `002` |
| Bazarr      | 3111              | 3200 (`media`) | read-write  | `002` |
| Lidarr      | 3112              | 3200 (`media`) | read-write  | `002` |
| qBittorrent | 3114              | 3200 (`media`) | read-write  | `002` |
| SABnzbd     | 3115              | 3200 (`media`) | read-write  | `002` |
| Sonarr      | 3116              | 3200 (`media`) | read-write  | `002` |
| TubeSync    | 3118              | 3200 (`media`) | read-write  | —     |

## Private Storage: Access Model

Private data (photos, documents) is intentionally separated from the shared media group hierarchy. Each category of private data gets its own dedicated group, ensuring services can only access the specific subdirectory they need — Immich cannot read a future documents directory, and a future documents service cannot read photos.

### Isolation Model

Access isolation is enforced at two layers:

1. **Parent dataset (`/mnt/archive-pool/private`):** Owned by `truenas_admin:truenas_admin` with Unix permissions 770 (no access for others). Same model as the `apps` dataset. This prevents any service account from traversing the parent path unless Docker mounts it directly — and Docker bind-mounts are resolved by the root daemon, so the container does not need host-path traversal rights.

2. **Subdirectory ownership via init containers:** Each service's init container chowns its specific subdirectory to the service's UID:GID. Because the parent dataset is root-inaccessible to service accounts, a service that doesn't have its path bind-mounted cannot reach sibling directories even if it somehow escapes its container.

### Per-Category Group Allocation

Each private data category has its own group. Services only receive the group for their specific category:

| GID  | Group               | Subdirectory                              | Service           |
| ---- | ------------------- | ----------------------------------------- | ----------------- |
| 3202 | `private-photos`    | `/mnt/archive-pool/private/photos/immich` | Immich (UID 3106) |
| 3203 | `private-documents` | `/mnt/archive-pool/private/documents/...` | Reserved          |

`truenas_admin` is added as an auxiliary group member of each group, granting admin access to each category's subdirectory after the init container sets ownership.

### TrueNAS Host Setup

On the TrueNAS host, create or confirm:

- A `private-photos` group (GID 3202), with `truenas_admin` as an auxiliary member
- A `svc-app-immich` user (UID 3106) with primary group `private-photos` (GID 3202)

On the parent private dataset (`/mnt/archive-pool/private`), using the TrueNAS **Unix Permissions Editor**:

| Setting | Value                    |
| ------- | ------------------------ |
| User    | `truenas_admin`          |
| Group   | `truenas_admin`          |
| User    | Read ✓ Write ✓ Execute ✓ |
| Group   | Read ✓ Write ✓ Execute ✓ |
| Other   | No permissions           |

No NFSv4 ACLs are needed on the parent dataset. Subdirectory permissions are managed entirely by init containers.

The init container chowns the service-specific subdirectory to the service UID:GID on every deploy. This is the single recovery point that restores access after any host-level permission reset.

### Container Configuration

Private-data containers hardcode the category-specific GID in `user:` directives and the init container:

```yaml
user: "3106:3202" # svc-app-immich:private-photos
```

### Adding a New Private-Data Service

1. Allocate the next GID from the `private-documents` row (3203+) in the Shared Purpose Groups table
2. Create the group on TrueNAS with that GID, add `truenas_admin` as auxiliary member
3. Create the service account user with its UID and the new group as primary
4. Add an init container that chowns the service's specific subdirectory under `/mnt/archive-pool/private/`
5. Bind-mount only that subdirectory into the container — never the parent `private/` path

## Historical Archives over SMB

**Setup status (2026-09-13):** The operator reported creating the new, empty
`archive-pool/archives` dataset and completing its NFSv4 / Restricted ACL setup.
This has not been independently host-verified. Other dataset settings (including encryption),
SMB share activation and file-transfer tests, off-site sync, and sample restores remain unverified.

The dedicated dataset, mounted at `/mnt/archive-pool/archives`, is intended for historical
blog backup archives, UniFi backups, password-manager exports, and similar imported files.
It is a top-level sibling of `content`, `private`, and `replication` on the mirrored HDD
pool, with independent ACLs and snapshots. The procedures below remain a setup reference;
skip completed dataset and ACL steps rather than recreating or resetting them.

Do not put these files under `vm-pool/apps` (live apps), `replication` (a managed replication
target), or `content` (shared media and its hardlink layout). Keeping the dataset outside
`private` avoids that parent's Unix `770` traversal restrictions; **the archives remain
private** through their own ACLs. Do not add container bind mounts or grant media/service-account
access. No new app user, fixed UID/GID allocation, or automated short-retention cleanup is needed.
This uses TrueNAS built-in SMB, not Compose, Traefik, a Custom App, or `dccd`.

### Create the Dataset

In **Datasets → archive-pool → Add Dataset**, create `archives` with the **SMB** preset.
UI labels vary by TrueNAS version; see the official
[dataset guide](https://www.truenas.com/docs/scale/datasets/managingdatasets/).

| Setting                      | Recommended value                                                             |
| ---------------------------- | ----------------------------------------------------------------------------- |
| Dataset name / mount path    | `archive-pool/archives` / `/mnt/archive-pool/archives`                        |
| Preset / ACL Type / ACL Mode | SMB / NFSv4 / Restricted; set explicitly unless inherited values are verified |
| Sync                         | Standard                                                                      |
| Compression                  | LZ4                                                                           |
| Enable Atime / Deduplication | Off / Off                                                                     |
| Case Sensitivity             | Insensitive; immutable after creation                                         |
| Checksum                     | On                                                                            |
| Read-only                    | Off, to permit SMB uploads                                                    |
| Exec                         | Off; prevents host-side execution, not execution on SMB clients               |
| Snapshot Directory           | Default / Invisible; hides `.zfs` from listings, does not schedule snapshots  |
| Snapdev                      | Hidden; applies to zvol snapshots, not this filesystem dataset                |
| Copies                       | 1 data copy per block; independent of the pool's mirror redundancy            |
| Record Size                  | 128 KiB; no archive-specific tuning needed                                    |
| Special Small Block Size     | 0                                                                             |
| Quota                        | Optional, sized to the actual collection and available pool capacity          |
| Encryption                   | Enable at creation, or inherit only after verifying parent encryption         |

These are recommended settings, not a verified inventory. **Inherit** follows the parent's
value; verify the effective value or set the property on `archive-pool/archives` explicitly.
Do not change the whole pool or sibling datasets just to obtain archive-specific properties.

Case sensitivity cannot be changed after creation. Case-insensitive naming is suitable for
storing original, unextracted archive files. Preserve the internal case of Linux website
trees inside their original archives rather than extracting them here.
Keep the dataset encryption key/passphrase independently of the NAS. If the dataset is
locked after a restart, unlock it before SMB access or Cloud Sync. ZFS encryption protects
data at rest, **not** against an authorized SMB user reading an unlocked dataset.

<!-- dprint-ignore -->
!!! warning "Changing ACL type does not migrate permissions"
    For a **new, empty dataset**, acknowledge the ACL-type warning, select **NFSv4** and
    **Restricted**, and create the dataset. There are no existing file ACLs to migrate,
    so no pre-change snapshot or recursive ACL application is needed. Manually define
    the dataset ACL with file and directory inheritance as described below.

    For an **existing, populated dataset**, take a snapshot **before** changing ACL type.
    Changing the format does not translate existing permissions. Review the replacement
    ACL and deliberately reapply it recursively only within the affected dataset if
    existing files need it; never blanket-reset the pool parent or sibling datasets.

### Restrict Filesystem and Share Access

1. Create or reuse a **personal, non-admin local user** with **SMB Access / Samba
   Authentication** enabled and a password. Do not log in to SMB as `root` or
   `truenas_admin`; do not enable guest access or create an app service account.
2. In **Datasets → archives → Permissions → Edit ACL**, define the new dataset's NFSv4
   ACL before uploading anything. Retain explicit owner/admin
   **Full Control**, using the documented administrative owner `truenas_admin` after
   confirming that account on the host. Grant the personal user **Modify**, with both
   file and directory inheritance on these entries. A named-user entry avoids adding a
   shared group. Leave recursive application off while the dataset is empty.
3. Review every preset/inherited entry: remove general data access for `builtin_users`,
   domain users, or `everyone@`. Ensure `group@` refers only to intended administrators,
   or remove its broad grants while retaining explicit admin access. Do not blindly trust
   the SMB preset or inherited ACL.
4. If parent traversal blocks access, stop and diagnose it separately. Do not broaden
   parent permissions or change `archive-pool` or sibling ACLs as part of this setup.
   **Never recursively reset permissions on the pool or sibling datasets.**
5. In **Shares → Windows (SMB)**, create a share named `archives` for
   `/mnt/archive-pool/archives`, using **Default Share** (or the version-equivalent basic
   SMB purpose). Leave read-only export **off** and guest access **disabled**.
   Dataset creation might already have created a share: edit it rather than duplicating it.
6. Restrict the **share ACL** as well as the filesystem ACL: allow the personal user
   **CHANGE**, and only intended administrators **FULL** if needed; remove default
   general/Everyone access. Both permission layers must allow the intended access.
   Enable the SMB service and automatic startup.
7. Enable **per-share SMB3 encryption** if supported by the installed version and clients.
   Do not change global settings for unrelated shares. Allow access only over a trusted
   LAN or VPN; never expose TCP 445 to the WAN.

The official [SMB share guide](https://www.truenas.com/docs/scale/shares/smb/addmanagesmbshares/)
describes local SMB-enabled users, share presets, and version-dependent UI controls.

### Connect and Import Safely

Connect as the personal SMB user:

- **Windows Explorer:** `\\svlnas\archives`
- **macOS Finder → Go → Connect to Server:** `smb://svlnas/archives`

First use harmless test files to verify create, read, rename, and delete operations.
Create a subfolder, disconnect/reconnect, and confirm new files and directories inherit
the intended permissions. Test with a different ordinary user and confirm access is denied.

Use ordinary folders such as `blog/`, `unifi/`, and `password-manager/`, not child datasets.
Keep dated original archives intact, with the originating application/version, restore notes,
and checksums alongside them. Use neutral filenames for sensitive material: the existing
Cloud Sync configuration encrypts file contents but **not filenames**.

<!-- dprint-ignore -->
!!! warning "Encrypt sensitive exports before copying"
    LastPass CSV exports are typically plaintext credentials. Encrypt them on the client
    with modern authenticated encryption before uploading; keep the recovery key/passphrase
    independently of the NAS and the export itself. Do not upload a plaintext CSV and then
    delete it: snapshots can retain it. Apply the same care to sensitive blog or UniFi backups.

**Copy first; do not move or delete the source originals.** Verify checksums against the
source and read files back, or perform a representative restore into an isolated target.
Then run and verify the snapshot/off-site steps in
[Historical Archive Protection](BACKUP.md#historical-archive-protection) before considering
any deliberate source cleanup.

## Multi-Server Deployment

This repository supports deploying apps to multiple servers beyond the primary TrueNAS host. Server-app mappings are defined in `servers.yaml` at the repo root.

### servers.yaml

The `servers.yaml` file maps servers to the apps they should deploy. Schema is validated by `servers.schema.json`.

```yaml
servers:
  svlazext:
    description: "Azure VM — DNS (AdGuard + Unbound), edge routing, and telemetry collection"
    age_public_key: "age1..."
    apps:
      - adguard
      - alloy
      # - cloudflared  # Temporarily disabled — no services to tunnel after hadiscover retirement
      - traefik
      - traefik-forward-auth
```

The `svlazext` server runs DNS filtering (AdGuard + Unbound), telemetry collection (Alloy), and Traefik with forward-auth for any externally-routed services. The Cloudflare Tunnel agent (`cloudflared`) is kept in the repo but commented out until a new public-facing service is added.

**TrueNAS (svlnas)** uses TrueNAS mode (`-t`) which has its own app discovery, but is listed in `servers.yaml` for SOPS key scoping.

### Deploying to a Server

Use the `-S <server>` flag with `dccd.sh`:

```sh
# Deploy only apps assigned to svlazext
bash scripts/dccd.sh -d /opt/apps -S svlazext -k /opt/apps/age.key -x shared -f

# Cron job example (runs every 5 minutes)
*/5 * * * * bash /opt/apps/scripts/dccd.sh -d /opt/apps -S svlazext -k /opt/apps/age.key -x shared
```

The `-S` flag:

- Reads `servers.yaml` and resolves the app list for the named server
- Only decrypts `secret.sops.env` files for those apps (not all apps)
- Only deploys compose stacks for those apps
- Auto-detects server-specific compose overrides (`compose.<server>.yaml`)
- Is mutually exclusive with `-a` (single app filter) and `-t` (TrueNAS mode)
- Requires `yq` on `PATH`

### Compose Overrides

Some apps (notably Traefik) need different configurations per server. Server-specific compose override files use the naming convention:

```text
services/<app>/compose.<server>.yaml
```

When `dccd.sh -S <server>` detects a matching override file, it automatically applies it using Docker Compose's multi-file syntax (`-f compose.yaml -f compose.<server>.yaml`). Docker Compose's list-replacement semantics mean the override cleanly replaces sections like the network list.

**Example**: Traefik on svlnas joins 25+ app frontend networks, but Traefik on svlazext only needs `adguard-frontend`. The override at `services/traefik/compose.svlazext.yaml` replaces the network list and adjusts labels.

Shared config (traefik.yml, rules/, TLS options) is reused via the same volume mounts — no config duplication.

### Per-Server Age Keys

Each server has its own Age keypair for SOPS decryption. The `.sops.yaml` creation_rules scope which servers can decrypt which app secrets:

```yaml
creation_rules:
  # adguard runs on svlnas + svlazext
  - path_regex: services/adguard/secret\.sops\.env$
    age: "deploy_key,svlnas_key,svlazext_key"
  # cloudflared runs on svlnas + svlazext
  - path_regex: services/cloudflared/secret\.sops\.env$
    age: "deploy_key,svlnas_key,svlazext_key"
  # traefik runs on svlnas + svlazext
  - path_regex: services/traefik/secret\.sops\.env$
    age: "deploy_key,svlnas_key,svlazext_key"
  # fallback: new apps default to deploy + svlnas
  - path_regex: secret\.sops\.env$
    age: "deploy_key,svlnas_key"
```

**Key roles**:

- **Deploy key**: Lives on your dev machine. Can decrypt everything. Used for `sops -e` / `sops -d` during development.
- **Server keys**: Each server stores only its own private key at `age.key`. It can only decrypt secrets for apps assigned to it.

Generate rules from `servers.yaml` using:

```sh
bash scripts/generate-sops-rules.sh -d /path/to/repo
```

The script reads the deploy key from `age.key` (the `# public key:` comment) and all server keys from `servers.yaml`. Servers without an `apps` list are treated as all-access.

After updating rules, re-encrypt all files: `sops updatekeys services/<app>/secret.sops.env` for each app.

### Docker Hub Authentication (dhi.io)

Several services use Docker Hardened Images from `dhi.io` (see [Architecture](ARCHITECTURE.md)). These require Docker Hub credentials even for pulling — unauthenticated pulls are rejected. `dccd.sh` will fail with a clear error if any compose file in scope references a `dhi.io` image but Docker has no stored credentials.

#### Automated approach (recommended)

Store a Docker Hub Personal Access Token in the SOPS-encrypted shared credentials file. `dccd.sh` decrypts this file on every run and automatically executes `docker login dhi.io` before pulling images — no manual per-server setup needed.

**Step 1 — Create a Docker Hub PAT**

1. Log in to [hub.docker.com](https://hub.docker.com)
2. Go to **Account Settings → Personal Access Tokens → Generate new token**
3. Give it a memorable description (e.g. `dhi-pull-<servername>`)
4. Set permissions to **Read-only** (pull is sufficient)
5. Copy the token — it is shown only once

**Step 2 — Create `services/shared/secret.sops.env`**

```sh
# On your dev machine (where the deploy Age key is available)
cat > /tmp/shared-secret.env <<'EOF'
DOCKERHUB_USERNAME=<your-dockerhub-username>
DOCKERHUB_TOKEN=<your-read-only-personal-access-token>
EOF

sops -e /tmp/shared-secret.env > services/shared/secret.sops.env
rm /tmp/shared-secret.env
```

The SOPS rule in `.sops.yaml` for `services/shared/secret.sops.env` includes all server Age keys, so every server can decrypt it. The file is committed encrypted; `dccd.sh` decrypts it to `services/shared/.env` at deploy time.

**How it works at runtime**

```
dccd.sh run
  └─ decrypt_sops_files()          # decrypts services/shared/secret.sops.env → services/shared/.env
  └─ auto_login_dhi()              # reads DOCKERHUB_USERNAME + DOCKERHUB_TOKEN, runs:
  │                                #   sudo docker login dhi.io --username ... --password-stdin
  └─ check_dhi_login()             # verifies root's Docker config has dhi.io credentials
  └─ docker compose pull ...       # succeeds because Docker is authenticated
```

#### Manual approach (one-time per server)

If you prefer not to store Docker Hub credentials in the repo, log in once on each server:

```sh
sudo docker login dhi.io
# Enter your Docker Hub username and a Personal Access Token when prompted
```

The credentials are stored in `/root/.docker/config.json` and persist across reboots. Re-run this command if the PAT expires or is rotated.

`dccd.sh` detects the existing credentials and proceeds without needing `services/shared/secret.sops.env`.

### Ansible Integration

Each remote server (Azure VMs) is managed by Ansible-pull which:

1. Clones this repository to the configured directory (e.g., `/opt/apps`)
2. Installs `yq` (required for server mode)
3. Places the server's Age private key at `<base_dir>/age.key`
4. Sets up a cron job running `dccd.sh -S <server>` at the desired interval

## Retiring an App

Retirement is the inverse of adding an app. Use the skill at `.github/skills/retire-docker-app/SKILL.md` for the full checklist — it covers removing compose files, Traefik networks/middleware, DNS records, documentation entries, and post-merge host cleanup.

Key mechanisms:

- **`dccd-down <app>`** (or `dccd.sh -R <app>`): Server-aware teardown that applies compose overrides and uses the correct project name for each deployment mode.
- **Auto-cleanup**: When `dccd.sh` pulls new commits that remove a service directory, it automatically detects the orphaned compose project and tears it down — no manual intervention needed on any server.
- **Retired services log**: Add an entry to `docs/RETIRED-SERVICES.md` with the retirement date, reason, and the last active commit hash so the old configuration is easy to find.
