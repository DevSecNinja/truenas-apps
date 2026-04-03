# Disaster Recovery

This document walks through rebuilding the Docker Compose app stack from scratch on a fresh or reinstalled TrueNAS system. It assumes the git repo and SOPS Age key are available (either from a backup or from another machine).

---

## Prerequisites

Before starting, ensure you have:

- A working TrueNAS installation with Docker support enabled
- Access to this git repository (GitHub)
- The **Age private key** (`age.key`) used for SOPS decryption — without this, secrets cannot be decrypted and no app will deploy. If the key is lost, every `secret.sops.env` must be re-encrypted with a new key
- (Optional) ZFS snapshots or replication backups of app datasets for data restoration

---

## Step 1: Create ZFS Datasets

Recreate the dataset hierarchy in the TrueNAS UI. Each app gets its own child dataset for independent snapshots and replication.

**Enable encryption on the `vm-pool/apps` dataset** when creating it. Use the TrueNAS encryption wizard to select a passphrase or key. Store the encryption passphrase/key in a secure, offline location (e.g., a password manager or printed copy) — without it, the dataset cannot be unlocked after a reboot or reinstall. Child datasets inherit encryption from the parent.

```text
vm-pool/apps              # root — holds the git repo
vm-pool/apps/src          # parent for all app datasets
vm-pool/apps/src/adguard
vm-pool/apps/src/echo-server
vm-pool/apps/src/gatus
vm-pool/apps/src/homepage
vm-pool/apps/src/immich
vm-pool/apps/src/metube
vm-pool/apps/src/plex
vm-pool/apps/src/traefik
vm-pool/apps/src/traefik-forward-auth
vm-pool/apps/src/unifi
```

### apps Dataset Permissions

Set Unix permissions on `vm-pool/apps` using the TrueNAS **Unix Permissions Editor**:

| Setting | Value                    |
| ------- | ------------------------ |
| User    | `truenas_admin`          |
| Group   | `truenas_admin`          |
| User    | Read ✓ Write ✓ Execute ✓ |
| Group   | Read ✓ Write ✓ Execute ✓ |
| Other   | No permissions           |

Enable **Apply permissions recursively**.

This ensures `truenas_admin` can manage the repo while decrypted `.env` files remain inaccessible to other users. Root does not need explicit permissions — it bypasses all permission checks.

---

## Step 2: Create Users and Groups

Every service runs as a dedicated non-root user. **Create groups first, then users** — if you rely on TrueNAS's "auto-create primary group" checkbox, it may assign a GID that does not match the UID.

### Shared Purpose Groups

Create these groups first since some service accounts reference them as their primary group:

> See the **Shared Purpose Groups** table in [ARCHITECTURE.md](ARCHITECTURE.md#shared-purpose-groups) for the full list of GIDs and their purpose.

For each shared group: create it in the TrueNAS UI with the designated GID. Add `truenas_admin` as an auxiliary member if admin access to those datasets is needed.

### App Service Accounts

For each app, follow this order:

1. Create group `svc-app-<name>` with the designated GID
2. Create user `svc-app-<name>` with the matching UID, primary group set to the group from step 1
3. Add `truenas_admin` to the group (grants group-write access to config files for `git pull`)

> See the **App Service Accounts** table in [ARCHITECTURE.md](ARCHITECTURE.md#app-service-accounts) for the full UID/GID allocation, user names, and which services each account covers.

### Group Memberships for Media and Private Access

Some service accounts need specific primary or auxiliary group memberships for media and private dataset access. See the [Shared Purpose Groups](ARCHITECTURE.md#shared-purpose-groups) and [Media Access](ARCHITECTURE.md#media-access-consumerprovider-model) sections in ARCHITECTURE.md for the full membership configuration.

---

## Step 3: Clone the Repository

Because the ZFS datasets from Step 1 already created the directory tree, a normal `git clone` will refuse to run ("destination path already exists"). Instead, initialise the repo inside the existing directory and check out `main`:

```sh
cd /mnt/vm-pool/apps
git init -b main
git remote add origin git@github.com:DevSecNinja/truenas-apps.git
git pull origin main
```

This overlays the repo contents onto the existing dataset mount points without conflicting with them.

---

## Step 4: Restore the Age Key

Place the Age private key on the TrueNAS host at the expected path:

```sh
# Copy from backup or another machine
cp /path/to/backup/age.key /mnt/vm-pool/apps/age.key
chmod 600 /mnt/vm-pool/apps/age.key
chown truenas_admin:truenas_admin /mnt/vm-pool/apps/age.key
```

Verify decryption works by testing one file:

```sh
sops -d /mnt/vm-pool/apps/src/echo-server/secret.sops.env
```

---

## Step 5: Restore Data (Optional)

If you have ZFS snapshots or replication backups, restore them **before** deploying apps:

- **Per-app datasets** — restore snapshots for `vm-pool/apps/src/<app>` to recover `data/` directories (databases, state files, certificates)
- **Named Docker volumes** — these live outside the dataset tree and need separate restoration if backed up. Key volumes include Traefik's ACME certificates (`traefik-acme`) and database data (`gatus-db-data`, etc.)
- **Database backups** — if using `tiredofit/db-backup`, restore from files in each app's `backups/` directory

If no backups are available, apps will start fresh — databases will be initialised empty and ACME certificates will be re-requested from Let's Encrypt.

---

## Step 6: Configure Media and Private Dataset Permissions (If Applicable)

If the archive pool was also lost or reformatted, recreate the media and private dataset permissions. See [ARCHITECTURE.md](ARCHITECTURE.md#media-access-consumerprovider-model) for the full ACL configuration for media datasets and [Private Storage](ARCHITECTURE.md#private-storage-access-model) for private datasets.

---

## Step 7: Create TrueNAS Custom Apps

In the TrueNAS UI, create a Custom App (YAML) for each service. Each entry uses the `include` directive to point at the compose file:

```yaml
include:
  - /mnt/vm-pool/apps/src/<app-name>/compose.yaml
services: {}
```

**Create Traefik last.** TrueNAS deploys each app immediately when you create it. Each app's compose file creates its own frontend network (e.g., `echo-server-frontend`), and Traefik's compose file references all of these as `external: true` — so those networks must already exist before Traefik is created.

---

## Step 8: Validate with the CD Script

After all apps are deployed via the TrueNAS UI, run the CD script once to verify everything is healthy and secrets decrypt correctly:

```sh
bash /mnt/vm-pool/apps/scripts/dccd.sh \
  -d /mnt/vm-pool/apps \
  -x shared \
  -t -f \
  -k /mnt/vm-pool/apps/age.key
```

Then check that all containers are healthy:

```sh
docker ps --format "table {{.Names}}\t{{.Status}}"
```

---

## Step 9: Re-enable the Cron Job

Add a TrueNAS cron job for continuous deployment:

- **Command:**
  ```sh
  bash /mnt/vm-pool/apps/scripts/dccd.sh -d /mnt/vm-pool/apps -x shared -t -f -k /mnt/vm-pool/apps/age.key
  ```
- **Run As User:** `root`
- **Schedule:** Every 15 minutes (or as desired)
- Unselect **Hide Standard Output** and **Hide Standard Error** for troubleshooting

---

## Recovery Checklist

Use this as a quick reference:

- [ ] Create ZFS datasets (`vm-pool/apps` hierarchy) with encryption enabled
- [ ] Unlock the encrypted apps dataset (if not auto-unlocked on boot)
- [ ] Set permissions on the apps dataset
- [ ] Create shared purpose groups (GIDs 3200–3202)
- [ ] Create app service accounts (UIDs 3100–3108, plus Plex at 911)
- [ ] Add `truenas_admin` to each app group
- [ ] Configure cross-group memberships (see ARCHITECTURE.md)
- [ ] Clone the git repository (as `truenas_admin`)
- [ ] Restore the Age private key
- [ ] Restore data from backups (if available)
- [ ] Recreate media/private dataset permissions (if applicable)
- [ ] Create TrueNAS Custom App entries in the UI (Traefik last)
- [ ] Run the CD script to validate
- [ ] Verify all containers are healthy
- [ ] Re-enable the cron job for continuous deployment
