# Docker Hardened Images (DHI) Migration

## Overview

This document tracks the migration of Docker images to their Docker Hardened Image (DHI) variants where available. DHI provides enhanced security through:

- **Minimal attack surface** — Distroless builds when possible, no shell, stripped of unnecessary OS components
- **Compliance** — CIS, FIPS, and STIG compliance built-in
- **Provenance** — Signed SBOMs and provenance metadata (SLSA Level 3+)
- **Security updates** — Continuous vulnerability scanning and patching
- **Free and open** — Available under Apache 2.0 license since December 2025

## DHI Registry

All DHI images are available at `dhi.io/<image-name>:<tag>`. Users need to authenticate with Docker Hub credentials:

```bash
docker login dhi.io
```

## Migration Status

### ✅ Migrated Services

The following services have been migrated to DHI variants:

1. **mosquitto** (`services/mosquitto/compose.yaml`)
   - **Before:** `docker.io/library/eclipse-mosquitto:2.1.2-alpine@sha256:a908c65cc8e67ec9d292ef27c2c0360dbaaee7eb1b935cdd194e67697f15dea1`
   - **After:** `dhi.io/mosquitto:2.1.2-alpine3.22@sha256:placeholder`
   - **Service:** MQTT broker for IoT devices

2. **traefik** (`services/traefik/compose.yaml`)
   - **Before:** `docker.io/library/traefik:v3.6.12@sha256:171c9c3565b29f6c133f1c1b43c5d4e5853415198e9e1078c001f8702ff66aec`
   - **After:** `dhi.io/traefik:3-alpine3.22@sha256:placeholder`
   - **Service:** Reverse proxy and load balancer

3. **postgres** (`services/outline/compose.yaml`, `services/gatus/compose.yaml`)
   - **Before:** `docker.io/library/postgres:18.3-alpine@sha256:4da1a4828be12604092fa55311276f08f9224a74a62dcb4708bd7439e2a03911`
   - **After:** `dhi.io/postgres:18.3-alpine3.22@sha256:placeholder`
   - **Services:** Database for Outline wiki and Gatus monitoring

4. **pgautoupgrade** (`services/outline/compose.yaml`, `services/gatus/compose.yaml`)
   - **Before:** `docker.io/pgautoupgrade/pgautoupgrade:18.3-alpine@sha256:fadc9788ee25f7acc040bbf485a880ce7ca9021575bd6e45b0ca4cf7edb50d5b`
   - **After:** `dhi.io/pgautoupgrade:18.3-alpine3.22@sha256:placeholder`
   - **Services:** PostgreSQL automatic upgrade tool

5. **redis** (`services/outline/compose.yaml`)
   - **Before:** `docker.io/library/redis:8.6.2-alpine@sha256:81b6f81d6a6c5b9019231a2e8eb10085e3a139a34f833dcc965a8a959b040b72`
   - **After:** `dhi.io/redis:8-alpine3.22@sha256:placeholder`
   - **Service:** Session/cache store for Outline

6. **mongo** (`services/unifi/compose.yaml`)
   - **Before:** `docker.io/library/mongo:8.2.6@sha256:eea8506335198f8b359865b32004036310854a935fbd317083817c614152818f`
   - **After:** `dhi.io/mongo:8-debian13@sha256:placeholder`
   - **Service:** Database for Unifi network controller

### ⏭️ Not Migrated (No DHI Variant Available)

The following images do not have DHI variants available at this time:

- **LinuxServer images** (`lscr.io/linuxserver/*`) — Already follow security best practices with s6-overlay
- **Application-specific images** — Immich, Home Assistant, ESPHome, Frigate, etc. (no DHI equivalents)
- **Third-party images** — AdGuard Home, Dozzle, Gatus, etc. (no DHI equivalents)
- **Custom/first-party images** — hadiscover, gatus-sidecar (built from source)

### 📋 Pending Actions

#### 1. Update Digest Hashes

The migration currently uses `@sha256:placeholder` digest values. These must be replaced with actual digest hashes before deployment. Two options:

**Option A: Manual digest lookup**
```bash
# Example for mosquitto
docker pull dhi.io/mosquitto:2.1.2-alpine3.22
docker inspect dhi.io/mosquitto:2.1.2-alpine3.22 | jq -r '.[0].RepoDigests[0]'
```

**Option B: Let Renovate manage digests**
- Merge the PR with placeholder digests
- Renovate will automatically detect the new images and create PRs to update the digests

#### 2. Test Deployment

Before deploying to production:

1. Authenticate with DHI registry:
   ```bash
   docker login dhi.io
   ```

2. Test pull access for each image:
   ```bash
   docker pull dhi.io/mosquitto:2.1.2-alpine3.22
   docker pull dhi.io/traefik:3-alpine3.22
   docker pull dhi.io/postgres:18.3-alpine3.22
   docker pull dhi.io/redis:8-alpine3.22
   docker pull dhi.io/mongo:8-debian13
   docker pull dhi.io/pgautoupgrade:18.3-alpine3.22
   ```

3. Validate compose files:
   ```bash
   docker compose -f services/mosquitto/compose.yaml config --quiet
   docker compose -f services/traefik/compose.yaml config --quiet
   docker compose -f services/outline/compose.yaml config --quiet
   docker compose -f services/gatus/compose.yaml config --quiet
   docker compose -f services/unifi/compose.yaml config --quiet
   ```

4. Deploy to a test environment first

#### 3. Update .sops.yaml for DHI Registry (if needed)

If DHI registry requires different credentials or age keys, update `.sops.yaml` accordingly.

## Verification

After deployment, verify that containers are using DHI images:

```bash
# Check running containers
docker ps --format 'table {{.Names}}\t{{.Image}}' | grep dhi.io

# Inspect container for provenance and SBOM
docker inspect <container-name> | jq -r '.[0].Config.Labels'
```

## Rollback Plan

If issues arise with DHI images, rollback is straightforward:

1. Revert the compose files to use the original `docker.io/library/*` images
2. Run `dccd.sh` to redeploy with the previous images
3. Monitor for stability

The original image references are preserved in this document and in git history.

## References

- [Docker Hardened Images Official Site](https://dhi.io)
- [DHI GitHub Catalog](https://github.com/docker-hardened-images/catalog)
- [DHI Documentation](https://docs.docker.com/hardened-images/)
- [Architecture Documentation](docs/ARCHITECTURE.md) — See "Image variant priority" section

## Next Steps

1. ✅ Migrate available images to DHI variants
2. ⏸️ Update placeholder digests with actual values (manual or via Renovate)
3. ⏸️ Test deployment in staging environment
4. ⏸️ Deploy to production via dccd.sh
5. ⏸️ Monitor for issues and verify improved security posture
6. ⏸️ Update docs/ARCHITECTURE.md to reflect DHI as the new standard
