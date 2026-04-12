# Troubleshooting

## Docker

Check all compose stack health at once:

```sh
sudo docker ps --format "table {{.Names}}\t{{.Status}}"
```

## DNS

### Quick Diagnostic Commands

Test AdGuard DNS directly from the NAS:

```sh
dig SVLNAS.<domain> @<router IP>
```

Test full external resolution chain via router:

```sh
dig google.com @<router IP>
```

Test DNSSEC chain:

```sh
dig +dnssec internetsociety.org @<router IP>
```

Test Quad9 DNS directly:

```sh
dig google.com @9.9.9.9
```

## Permissions

This section covers debugging file-permission errors on TrueNAS datasets. For the full permission model, see [INFRASTRUCTURE.md § UID/GID Allocation](INFRASTRUCTURE.md#uidgid-allocation) and [§ Media Access](INFRASTRUCTURE.md#media-access).

### Which ACL Type Is a Dataset Using?

```sh
zfs get acltype <pool>/<dataset>
```

| Value      | Meaning                                    |
| ---------- | ------------------------------------------ |
| `nfsv4`    | NFSv4 ACLs (TrueNAS Scale default for ZFS) |
| `posixacl` | POSIX ACLs                                 |
| `off`      | Simple Unix permissions only               |

Also check how `chmod` interacts with the ACL:

```sh
zfs get aclmode <pool>/<dataset>
```

### Dataset ACL Summary

| Dataset                       | ACL type   | Rationale                                                                                    |
| ----------------------------- | ---------- | -------------------------------------------------------------------------------------------- |
| `vm-pool/apps`                | Unix perms | Init containers use `chown`/`chmod` freely; simple model matches the init-container pattern  |
| `archive-pool/content`        | Unix perms | Single dataset for media + future downloads; single `media` group (GID 3200); setgid + UMASK |
| `/mnt/archive-pool/private/*` | Unix perms | Per-category group isolation (photos, documents) via init-container chown                    |

### "Permission Denied" on a Media Dataset

Media datasets use plain Unix permissions (`acltype=off`). The full picture is visible with `ls -la` — no hidden ACL entries.

**Diagnose:**

```sh
# Check dataset acltype is off (should show 'off')
zfs get acltype archive-pool/content

# Check ownership and mode
ls -la /mnt/archive-pool/content/media/

# Test access as the specific service UID
sudo -u '#3107' ls /mnt/archive-pool/content/media/youtube/metube   # MeTube write test
sudo -u '#911'  ls /mnt/archive-pool/content/media/movies           # Plex read test
```

**Expected state for each media dataset:**

- Owning group: `media` (GID 3200)
- Directory mode: `2775` (rwxrwsr-x) — setgid ensures new subdirs inherit the group
- File mode: `664` (rw-rw-r--) — created by producers with UMASK=002

**Fix if ownership or mode is wrong:**

```sh
chown -R :3200 /mnt/archive-pool/content
find /mnt/archive-pool/content -type d -exec chmod 2775 {} +
find /mnt/archive-pool/content -type f -exec chmod 664 {} +
```

### New Files Created by MeTube Are Unreadable by Plex

Two things must both be true:

1. **Setgid bit on parent directories:** Each media dataset directory must have the setgid bit set (`chmod g+s`). Verify:

   ```sh
   # Look for 's' in the group execute column (e.g. drwxrwsr-x)
   ls -la /mnt/archive-pool/content/media/youtube/
   ```

   Without the setgid bit, new files and subdirectories inherit MeTube's primary group (`media`, GID 3200) only because MeTube's primary group IS `media`. If the primary group ever changes, inheritance breaks. The setgid bit makes this unconditional.

2. **UMASK=002 in the MeTube container:** MeTube must set `UMASK=002` so created files are group-readable (`664`). Check the compose file:

   ```yaml
   environment:
     - UMASK=002
   ```

   Without `UMASK=002`, the default `022` makes files owner-writable only (`644`), so the `media` group cannot read them.

### Debugging Checklist

When a container cannot read or write a file on a TrueNAS dataset:

1. **Verify the container's UID/GID.** Check `user:` in the compose file, or `PUID`/`PGID` for s6-overlay images. Confirm with `docker exec <container> id`.
2. **Identify the dataset.** Run `zfs list` on TrueNAS and find which dataset the path belongs to.
3. **Check the ACL type.** Run `zfs get acltype <pool>/<dataset>`:
   - If `off` → standard Unix permissions. Use `ls -la` and verify owner/group/other bits.
   - If `nfsv4` → inspect with `nfs4_getfacl <path>` and look for the container's UID or GID.
4. **Check group membership.** Confirm the service account is in the `media` group:

   ```sh
   id svc-app-metube
   id svc-app-plex
   ```

5. **Test access from the host.** Switch to the service account's UID and try the operation:

   ```sh
   sudo -u '#3107' ls /mnt/archive-pool/content/media/youtube/metube
   ```

6. **Check the Compose mount mode.** A volume mounted `:ro` blocks writes at the kernel level regardless of filesystem permissions.
