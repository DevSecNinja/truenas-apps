# changedetection.io

[changedetection.io](https://changedetection.io/) monitors websites for changes,
retains diffs, and sends notifications. This deployment currently uses Basic
HTTP only; JavaScript rendering, new screenshots, and browser steps are disabled.

## Why

Keep watch definitions and history on locally managed storage behind the
existing SSO boundary. A DHI browser and filtering proxy are staged but
disabled pending a verified patched browser image.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/changedetection/compose.yaml)

## Access and Authentication

| Property       | Configuration                                                     |
| -------------- | ----------------------------------------------------------------- |
| URL            | `https://changedetection.${DOMAINNAME}`                           |
| Traefik router | `changedetection-rtr`, HTTPS, `chain-auth@file`                   |
| App listener   | Fixed internal port `5000`; no host-published port                |
| API access     | Behind the same SSO middleware as the entire UI; no bypass router |
| Monitoring     | Container health checks; no Gatus integration                     |

An application API key does not bypass Traefik SSO. An optional application
password can be configured under **Settings** as an additional control; this
is not a new-user account registration flow.

## Architecture

The application uses the upstream-supported
`docker.io/dgtlmoon/changedetection.io:0.60.7` image, pinned to
`sha256:096dae27b5d677b89f0e810fff95a70403271aa3ff3b6437952d2db9be7e74c5`.
No smaller or DHI alternative has been adopted for the application itself.

### Services

| Container                       | Role                                                                                                                                                  |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `changedetection`               | Web UI, API, and fetch workers; writes only persistent `/datastore` and temporary paths                                                               |
| `changedetection-browser-proxy` | Staged stateless Squid proxy; disabled by default                                                                                                     |
| `changedetection-chrome`        | Staged DHI browser; disabled by default and blocked by a minimum-version gate                                                                         |
| `changedetection-init`          | `docker.io/library/busybox:1.38.0`; validates `DOMAINNAME`, chowns `./data` mounted at `/datastore` to UID/GID `3131:3131`, and applies `u=rwX,g=,o=` |

The app runs as `svc-app-changedetection` with matching UID and primary GID
from the [identity allocation](../INFRASTRUCTURE.md#app-service-accounts), no
shared groups, and `admin_group_member=false`. Init runs as root with only
`CHOWN`, `FOWNER`, and `DAC_OVERRIDE` added back, no network, and a read-only
root filesystem. It never changes `./config`.

The app waits only for successful init completion, not Chrome. The staged
Chrome definition still depends on a healthy browser proxy.
Only one application instance may write the datastore: Compose specifies
stop-first updates and a 60-second graceful-stop period.

### Browser and Networks

**Current mode: Basic HTTP only.** `DEFAULT_FETCH_BACKEND=html_requests` and
an empty `PLAYWRIGHT_DRIVER_URL` disable browser fetching. Chrome and Squid
both belong to `browser-pending-security-update`, which is off by default.
Existing browser-backed watches must be manually changed to **Basic HTTP**;
the deployment does not silently migrate persisted watch settings.

Both apps stage `dhi.io/playwright:1.63.0-debian13` as separate browser
instances. Initial DHI adoption is tag-only; Renovate will add the digest pin.
The inspected image contains vulnerable Chromium `153.0.8010.47-2~deb13u1`,
below the launcher's `153.0.8010.52` minimum. It is **not ready to enable**.
See the [security gate and future enablement requirements](../ARCHITECTURE.md#browser-egress-policy-public-websites-only).

<!-- dprint-ignore -->
!!! warning "An inactive profile does not stop an old browser"
    If already deployed, explicitly stop the old `changedetection-chrome`
    container and its browser proxy if present, then verify they are stopped.
    Do not assume dccd or the inactive profile removes running containers.
    Keep the browser profile off; enabling `COMPOSE_PROFILES` alone would not
    configure the app's fetcher and must not be used with the vulnerable image.

Browser/proxy memberships below describe the staged definitions, not running
services in the default HTTP-only deployment.

| Network                          | Members and purpose                                                                     |
| -------------------------------- | --------------------------------------------------------------------------------------- |
| `changedetection-browser`        | App, Chrome, and browser proxy; private, internal, IPv4-only CDP and HTTP proxy traffic |
| `changedetection-browser-egress` | Browser proxy only; outbound connections to permitted public websites                   |
| `changedetection-frontend`       | App and Traefik; UI/API traffic and app egress                                          |

The reserved CDP relay endpoint is `http://172.30.100.22:9222`; it is **not**
currently assigned to `PLAYWRIGHT_DRIVER_URL`. The read-only
`../shared/config/browser/launch.mjs` checks the Chromium version before
launch and, only after that check passes, relays port `9222` to Chromium on
loopback port `9223`. This stages a stable HTTP discovery endpoint without
claiming that the DHI browser integration has passed.

The control subnet is `172.30.100.16/29`, with dynamic allocation limited to
`172.30.100.16/30`; Chrome's `172.30.100.22` reservation is outside that
dynamic range. Keep IPAM and `ipv4_address` coordinated; any future driver URL
requires review and integration testing.
See the [network and access model](../ARCHITECTURE.md#changedetectionio-network-and-access-model).

| Setting                   | Default and purpose                                           |
| ------------------------- | ------------------------------------------------------------- |
| `DEFAULT_FETCH_BACKEND`   | `html_requests`; Basic HTTP only                              |
| `PLAYWRIGHT_DRIVER_URL`   | Empty; browser fetching disabled                              |
| `FETCH_WORKERS`           | `${FETCH_WORKERS:-2}`; adjustable concurrency                 |
| `MEM_LIMIT`               | `${MEM_LIMIT:-1024m}`; application memory bound               |
| `CHROME_MEM_LIMIT`        | `${CHROME_MEM_LIMIT:-2048m}`; staged browser memory bound     |
| `BROWSER_PROXY_MEM_LIMIT` | `${BROWSER_PROXY_MEM_LIMIT:-256m}`; staged proxy memory bound |
| `TZ`                      | Supplied to all four containers by `../shared/env/tz.env`     |

The staged Chrome definition uses DHI's non-root identity (`65532:65532`), with
`init: true`, `cap_drop: ALL`, `no-new-privileges`, a read-only root filesystem,
temporary filesystems, and a 100-PID limit. The app also drops all capabilities,
has a read-only root filesystem, and uses a 100-PID limit. Chrome has no
published ports, no Traefik labels, and no frontend network membership.

#### Public-Website-Only Browser Egress

If approved for future use, the staged Chrome definition joins **only**
`changedetection-browser`, with no direct internet route. Its command sets:

- `--proxy-server=http://changedetection-browser-proxy:3128`
- `--proxy-bypass-list=<-loopback>` to remove the implicit loopback bypass
- `--disable-quic`
- `--force-webrtc-ip-handling-policy=disable_non_proxied_udp`

The dedicated proxy uses the operator-approved, digest-pinned Canonical image
`docker.io/ubuntu/squid:7.2-26.04_edge`. It mounts
`../shared/config/browser/squid.conf` read-only and allows only permitted
public destinations on ports `80`/`443`, with `CONNECT` restricted to `443`.
Private/reserved destinations and IPv6 transition paths are filtered by the
[shared browser egress policy](../ARCHITECTURE.md#browser-egress-policy-public-websites-only).

The proxy runs as `65534:65534`, with a read-only root, `cap_drop: ALL`,
`no-new-privileges`, a 100-PID limit, and only `/tmp` as writable scratch.
It has no published ports, persistent state, disk cache, or URL access log.
The bundled Perl health check requires an actual HTTP `403` for a loopback
destination. Both staged services watch `../shared/config/browser` through
`config.watch` and `config.sha256`, covering the launcher and Squid policy
together. Config-change recreation applies when services are enabled; it does
not activate the profile. No custom image publication is needed.

<!-- dprint-ignore -->
!!! warning "Public websites only; residual browser risk remains"
    Internal-site monitoring is intentionally unsupported. Do not add
    `DIRECT` fallbacks, bypass rules, extra Chrome egress networks, or
    unreviewed per-watch proxy overrides to work around denials. The policy
    targets browser HTTP(S) redirect/subresource SSRF, not every app fetch
    path or arbitrary watch proxy override. The staged launcher uses
    `--no-sandbox`; a native-code compromise could reach its app and proxy
    peers on the shared internal control network. This is not full
    native-code compromise containment or protection against browser zero-days.

## Secrets

| Variable     | Classification                                     | Handling                                                                                                |
| ------------ | -------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `DOMAINNAME` | Non-secret, user-supplied deployment configuration | Reuses the existing deployment domain, encrypted in `secret.sops.env` through the canonical SOPS helper |

This is the only SOPS variable. There are **no generated bootstrap secrets**
and no database-encryption passphrase. The application generates its own
session/API secrets in persisted state. Preserve that state rather than
attempting to recreate these values in the environment.

Use the [SOPS editing workflow](../CONTRIBUTING.md#safe-human-review) for
configuration changes. Never commit decrypted `.env` or datastore contents.

## Persistent State and Backup

| Host path | Container path | Classification and contents                                                                                    |
| --------- | -------------- | -------------------------------------------------------------------------------------------------------------- |
| `./data`  | `/datastore`   | **Critical mutable file state**: global/watch/tag JSON files, `secret.txt`, history snapshots, and screenshots |

Retain existing screenshots/history when switching to HTTP-only operation;
disabling browser execution does not remove stored files or rewrite watches.

This is **not SQLite or another formal database**. There is no database backup
sidecar and no encrypted database dump. The entire directory belongs to
`vm-pool/apps/services/changedetection` and is covered by the existing
vm-pool snapshot, cross-pool replication, and encrypted off-site Cloud Sync
layers. Chrome's temporary profile and caches are ephemeral. The browser
proxy is stateless and adds no database or backup requirement.

<!-- dprint-ignore -->
!!! warning "Live file snapshots are not application-consistent"
    A live filesystem snapshot can capture related files at different stages
    of an application update. Gracefully stop the app before a manual
    consistent snapshot or full-directory export. Restore the complete
    datastore while stopped, not selected JSON files over a live instance.
    The upstream ZIP backup may have limited history coverage; do not assume
    it is a complete datastore backup.

See [Restore changedetection.io file state](../BACKUP.md#restore-changedetectionio-file-state)
for safe recovery steps and version-pinned upstream storage references.

### Validation Status

Before the browser-egress remediation, a three-container baseline test used
the exact app, Chrome, and init image digests then configured on **Linux
amd64**, with **rootless Podman 5.8.3** and **Compose 5.4.0**. The results below
are historical baseline evidence, not proof that the staged DHI browser
works, is patched, or is safe to enable.

| Check                    | Observed result                                                                                                                   |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| Startup                  | App and Chrome healthy; init exited `0`                                                                                           |
| App hardening            | UID/GID `3131:3131`, no capabilities, `no-new-privileges`, read-only root, writable `/tmp` and `/datastore`                       |
| Browser hardening        | UID `65534`, read-only root                                                                                                       |
| Resources and networking | Both app and Chrome had the configured memory limits and 100-PID limits; no published ports; expected isolated network membership |
| Browser operation        | Playwright connected through HTTP CDP, clicked a JavaScript button, and captured a screenshot                                     |
| Persistent watch         | The app API created a synthetic browser watch that produced persisted history and a PNG screenshot                                |

For the file-state restore test, the app was gracefully stopped and the
**entire datastore** was archived with tar. The original tree was retained,
the archive was restored into a fresh directory, and init was rerun
successfully (exit `0`). After force-recreating Chrome and the app, the same
synthetic watch, history, and screenshot were verified, along with HTTP CDP
rediscovery.

This validates one app's synthetic file-state backup/restore, **not a database
restore**. It was not a TrueNAS production deployment or a test of ZFS,
replication, or off-site recovery. Synthetic proxy auth routing passed with
disposable Traefik `3.7.10`, the actual app router/middleware labels, and
synthetic Forward Auth: both UI and API returned `401` without authorization
and `200` with authorization. Real Entra/production SSO, TLS termination,
and interactive visual-selector tests remain pending.

The new Squid proxy separately passed public HTTP and certificate-validated
HTTPS tests and controlled denial tests for private literals/hostnames,
IPv4-mapped IPv6, NAT64, 6to4, forbidden ports, and disallowed `CONNECT`.
Those tests used only the controlled proxy, not connections to real LAN
services. Those results do not validate the DHI browser. **The current
mitigation is to disable browser execution**, not to restore active JavaScript
features. Future enablement requires a verified patched DHI image, browser
integration tests, and reviewed app environment/dependency changes. See
[proxy validation and limits](../ARCHITECTURE.md#browser-egress-policy-public-websites-only)
and the [rootful test-runtime requirement](../INFRASTRUCTURE.md#stateless-browser-proxies).

## First-Run Setup

After merge, run these steps on TrueNAS in this order. Source the aliases first:

```sh
source /mnt/vm-pool/apps/scripts/aliases.sh
```

1. Pull the merged changes and decrypt configuration for the new app:

   ```sh
   dccd-app changedetection
   ```

   The missing TrueNAS app config directory and skipped deployment are
   expected before the Custom App exists. Do not run `dccd-all` first:
   Traefik may reference the new frontend network before it exists.
2. Provision the registry-declared account, group, and child dataset:

   ```sh
   cd /mnt/vm-pool/apps
   sudo bash scripts/truenas-prep-app.sh changedetection
   ```

   The helper preserves the checked-out service files.
3. Create the Custom App in the TrueNAS UI.

   **TrueNAS Custom App name:** `changedetection`

   ```yaml
   include:
       - /mnt/vm-pool/apps/services/changedetection/compose.yaml
   services: {}
   ```

4. Run the canonical final deployment:

   ```sh
   dccd-all
   ```

   This deploys the apps and dependent AdGuard/Traefik changes in the normal
   order. Its database-backup freshness check does not validate this app's
   file-state backups.
5. Sign in through SSO at `https://changedetection.${DOMAINNAME}`:
   - Remove the demo watches.
   - Set the check interval, confirm the timezone, and select **Basic HTTP**.
   - Add a public-website HTTP watch whose content does not require JavaScript;
     verify fetched content and a diff after a change.
   - If any existing watch uses a browser fetcher, manually select **Basic
     HTTP** for that watch. Do not silently rewrite stored watch settings.
   - Configure a notification destination and send a test notification.
   - Optionally set an application password under **Settings**; do not look
     for a new-user account flow.
6. Verify init completed, the app is healthy, and unauthenticated UI/API
   requests remain behind SSO. Confirm old browser containers are stopped and
   the browser profile remains inactive. Do not expect JavaScript rendering,
   new screenshots, browser steps, or the visual selector in HTTP-only mode.

## Upgrade Notes

- Review upstream release notes and Renovate image changes before deployment.
- Gracefully stop the app and capture a complete datastore recovery point
  before an upgrade that may change stored files.
- Do not run old and new app instances against the same datastore.
- Recheck Basic HTTP fetching, diffs, and notifications after upgrades. Keep
  browsers disabled during upgrades and restores until the patched-image
  and integration requirements have been met; do not lower the version gate.
- If rollback requires older file formats, restore the matching complete
  pre-upgrade state with the corresponding image version. Keep the failed
  tree until recovery is verified.
