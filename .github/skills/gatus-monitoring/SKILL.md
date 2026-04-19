---
name: gatus-monitoring
description: >
    Configure Gatus health monitoring for a service in this repository. Use when
    adding health-check labels to a new or existing service, updating monitoring
    configuration, or checking that a service is correctly wired into Gatus.
argument-hint: "Name the service to configure Gatus monitoring for (e.g. 'immich')"
---

# Configure Gatus Health Monitoring

## When to Use

- Adding Gatus monitoring labels to a new service's `compose.yaml`
- Fixing a service that is missing Gatus monitoring
- Updating the health-check URL path for a service
- Adding a non-Docker endpoint to `services/gatus/config/config.yaml`

## Background

Gatus health checks in this repo use two mechanisms:

1. **Sidecar labels** (primary) — labels on each service's container that
   `gatus-sidecar` reads from the Docker socket and injects into Gatus automatically.
   Use this for any Docker-managed service.

2. **Static config** (`services/gatus/config/config.yaml`) — hand-written YAML for
   non-Docker endpoints (TCP ports, external URLs, IoT devices, etc.).
   Use this for anything not running as a Docker service.

The Gatus sidecar polls containers in the `gatus-backend` network via the Docker
socket. All services share the Traefik health-check entrypoint on port **8444**
(internal only, not published to the host) at the static Traefik IP **172.30.100.6**.

## Sidecar Label Pattern

Add these labels to the **main application container** (not init or sidecar
containers). Always place them in the same `labels:` block as the Traefik labels.

### Standard pattern (no-auth services)

Services using `chain-no-auth@file` — Traefik serves the request without a redirect:

```yaml
labels:
  # Gatus
  - "gatus.url=http://172.30.100.6:8444"
  - "gatus.headers.Host=<subdomain>.${DOMAINNAME}"
  - 'gatus.conditions=["[STATUS] == 200", "[RESPONSE_TIME] < 1000"]'
  - 'gatus.alerts=[{"type": "email"}, {"type": "custom"}]'
```

### Auth-protected services (chain-auth)

Services using `chain-auth@file` redirect unauthenticated requests to the OAuth
provider. Add `ignore-redirect: true` so Gatus accepts the 302/307:

```yaml
labels:
  # Gatus
  - "gatus.url=http://172.30.100.6:8444"
  - "gatus.headers.Host=<subdomain>.${DOMAINNAME}"
  - 'gatus.client={"ignore-redirect": true}'
  - 'gatus.conditions=["[STATUS] == 200", "[RESPONSE_TIME] < 1000"]'
  - 'gatus.alerts=[{"type": "email"}, {"type": "custom"}]'
```

### Services with a dedicated health endpoint

When the app's root path (`/`) returns something unhelpful (e.g. a redirect loop or
HTML login page) but the app exposes a dedicated API path, use that path instead:

```yaml
labels:
  # Gatus
  - "gatus.url=http://172.30.100.6:8444/<health-path>"
  - "gatus.headers.Host=<subdomain>.${DOMAINNAME}"
  - 'gatus.conditions=["[STATUS] == 200", "[RESPONSE_TIME] < 1000"]'
  - 'gatus.alerts=[{"type": "email"}, {"type": "custom"}]'
```

Common health paths used in this repo:

| Service | Path |
| ------- | ---- |
| Dozzle | `/healthcheck` |
| Frigate | `/api/version` |
| Immich | `/api/server/ping` |
| Lidarr / Prowlarr / Radarr / Sonarr / Bazarr | `/ping` |
| Traefik | `/api/overview` |

If you are unsure whether an app has a health endpoint, check its upstream documentation
or look for a `/health`, `/healthz`, `/ping`, or `/api/health` path.

### Disabling monitoring

Services that should not be monitored (e.g. Gatus itself, database sidecars, backup
containers, internal-only services) use:

```yaml
labels:
  # Gatus
  - "gatus.enabled=false"
```

## Determining the Correct Pattern

| Condition | Pattern |
| --------- | ------- |
| Service uses `chain-no-auth@file` middleware | Standard (no `ignore-redirect`) |
| Service uses `chain-auth@file` middleware | Add `gatus.client={"ignore-redirect": true}` |
| Service has a dedicated `/ping` or `/health` endpoint | Use that path in `gatus.url` |
| Service is internal-only (no Traefik route) | Add to static `config.yaml` instead |
| Service is a background helper (init, sidecar, DB) | `gatus.enabled=false` |
| Service IS Gatus | `gatus.enabled=false` |

Read the service's Traefik middleware label to determine the auth pattern:

```yaml
- "traefik.http.routers.<name>-rtr.middlewares=chain-auth@file"
```

## Adding to Static Config (Non-Docker Services)

For TCP/UDP endpoints, IoT devices, or external URLs, add an entry to
`services/gatus/config/config.yaml`:

### HTTP endpoint

```yaml
- name: <display-name> - HTTP
  <<: *defaults
  url: "http(s)://<host>:<port>/<path>"
  group: Internal   # or External
  conditions:
    - "[STATUS] == 200"
    - "[RESPONSE_TIME] < 1000"
```

### TCP endpoint

```yaml
- name: <display-name> - TCP
  <<: *tcp-udp-defaults
  url: "tcp://${IP_SVLNAS}:<port>"
```

Keep entries grouped by type (External HTTP, Internal HTTP, TCP/UDP) and sorted
alphabetically by name within each group.

## Procedure

### Step 1 — Identify the service

Read `services/<app>/compose.yaml`. Find the main container (not init/sidecar).

### Step 2 — Determine the auth pattern

Check the Traefik middleware label:

- `chain-no-auth@file` → standard pattern
- `chain-auth@file` → add `ignore-redirect: true`
- No Traefik labels (internal-only service) → use static config

### Step 3 — Determine the health URL path

Check if the service exposes a dedicated health endpoint:

1. Look at the healthcheck `test:` in the compose file — it often shows the path
2. Check upstream docs for `/ping`, `/health`, `/healthz`, `/api/health`
3. Default to `/` if no dedicated path exists

### Step 4 — Add the labels

Add the Gatus labels to the main container's `labels:` block, immediately after
or before the Traefik labels. Use the correct pattern from the reference above.

### Step 5 — Validate

Check that the compose file is still valid:

```sh
docker compose -f services/<app>/compose.yaml config --quiet
```

Verify the label block looks correct (no YAML syntax errors, correct quoting).

## Label Quoting Rules

- Use double quotes (`"…"`) for simple string values: `"gatus.url=…"`, `"gatus.headers.Host=…"`
- Use single quotes (`'…'`) for JSON values that contain double quotes:
  `'gatus.conditions=["[STATUS] == 200"]'`
- Never mix quote styles within the same label value

## Checklist

- [ ] Gatus labels are on the main container (not init/backup/DB containers)
- [ ] `gatus.url` uses `http://172.30.100.6:8444` (not HTTPS, not a Docker service name)
- [ ] `gatus.headers.Host` uses `<subdomain>.${DOMAINNAME}` (not a hardcoded domain)
- [ ] `ignore-redirect` is set for auth-protected services
- [ ] Dedicated health path is used where the root returns an unhelpful response
- [ ] Background services have `gatus.enabled=false`
- [ ] `docker compose config --quiet` passes
