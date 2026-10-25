# Retired Services

Services removed from this repository. The "Last Active Commit" column identifies
the old configuration for inspection or selective restoration, not a reason to
roll back the whole repository.

| Service       | Retired Date | Reason                                                   | Last Active Commit                                                                                       | Issue/PR                                                       |
| ------------- | ------------ | -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| bazarr        | 2026-10-25   | Unused; datasets and identities retained                 | [`f73f9a4`](https://github.com/DevSecNinja/truenas-apps/commit/f73f9a451a9efb9f501f1019fc22c8e088302cb5) | —                                                              |
| hadiscover    | 2026-05-17   | Upstream hadiscover app no longer requires a backend API | [`6efe7d3`](https://github.com/DevSecNinja/truenas-apps/commit/6efe7d3)                                  | —                                                              |
| lidarr        | 2026-10-25   | Unused; datasets and identities retained                 | [`f73f9a4`](https://github.com/DevSecNinja/truenas-apps/commit/f73f9a451a9efb9f501f1019fc22c8e088302cb5) | —                                                              |
| openspeedtest | 2026-04-11   | Upstream unmaintained; image >365 days stale             | [`d9e67be`](https://github.com/DevSecNinja/truenas-apps/commit/d9e67be)                                  | [#149](https://github.com/DevSecNinja/truenas-apps/issues/149) |
| prowlarr      | 2026-10-25   | Unused; datasets and identities retained                 | [`f73f9a4`](https://github.com/DevSecNinja/truenas-apps/commit/f73f9a451a9efb9f501f1019fc22c8e088302cb5) | —                                                              |
| qbittorrent   | 2026-10-25   | Unused; datasets and identities retained                 | [`f73f9a4`](https://github.com/DevSecNinja/truenas-apps/commit/f73f9a451a9efb9f501f1019fc22c8e088302cb5) | —                                                              |
| radarr        | 2026-10-25   | Unused; datasets and identities retained                 | [`f73f9a4`](https://github.com/DevSecNinja/truenas-apps/commit/f73f9a451a9efb9f501f1019fc22c8e088302cb5) | —                                                              |
| sabnzbd       | 2026-10-25   | Unused; datasets and identities retained                 | [`f73f9a4`](https://github.com/DevSecNinja/truenas-apps/commit/f73f9a451a9efb9f501f1019fc22c8e088302cb5) | —                                                              |
| sonarr        | 2026-10-25   | Unused; datasets and identities retained                 | [`f73f9a4`](https://github.com/DevSecNinja/truenas-apps/commit/f73f9a451a9efb9f501f1019fc22c8e088302cb5) | —                                                              |
| spottarr      | 2026-10-25   | Unused; datasets and identities retained                 | [`f73f9a4`](https://github.com/DevSecNinja/truenas-apps/commit/f73f9a451a9efb9f501f1019fc22c8e088302cb5) | —                                                              |

## Arr Stack Retirement

**Scope:** retire exactly Bazarr, Lidarr, Prowlarr, qBittorrent, Radarr, SABnzbd,
Sonarr, and Spottarr together because they are unused. **Plex remains active.**
The date above records repository retirement, not a completed production teardown.

| Resource                                           | Retirement policy                                                                                                                                                         |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Eight app stacks and their live integrations       | Remove from deployment, routing, discovery, monitoring, and active provisioning                                                                                           |
| Shared `_bootstrap`                                | Retain `content-init`, `arr-egress-init`, its SOPS/DDNS/egress configuration, and all four networks: `arr-egress`, `arr-stack-backend`, `dawarich-backend`, `iot-backend` |
| `vm-pool/apps/services/<app>` for each retired app | Retain the dataset, all runtime data, configuration, and backups                                                                                                          |
| `archive-pool/content`                             | Retain all `media/` and `downloads/` data and the single-filesystem layout                                                                                                |
| Plex                                               | Keep its stack, dataset, media access, routing, and monitoring                                                                                                            |
| Accounts, groups, and ownership IDs                | Retain existing identities and memberships; never reallocate them                                                                                                         |
| Existing Docker volumes                            | Retain; no volume cleanup is part of this retirement                                                                                                                      |

See [retained datasets](INFRASTRUCTURE.md#retained-arr-datasets),
[account reservations](INFRASTRUCTURE.md#retained-arr-account-reservations),
and [backup coverage](BACKUP.md#retained-arr-state).

### Operator Handoff

Coordinate scheduled DCCD runs and manual deployments so nothing restarts the
retired apps between shutdown and the retirement merge/pull. These are operator
steps on TrueNAS, not actions already performed by this documentation change.

1. **Before merge/pull**, while the old Compose files still exist, source the
   deployment aliases and stop only the eight retired stacks:

   ```bash
   source /mnt/vm-pool/apps/scripts/aliases.sh
   dccd-down bazarr lidarr prowlarr qbittorrent radarr sabnzbd sonarr spottarr
   ```

   `dccd-down` invokes `dccd.sh -R` for each app. On TrueNAS the projects are
   named `ix-<app>`. With Compose present it uses `down --remove-orphans`,
   **without `--volumes`**; if Compose is missing it falls back to project-label
   cleanup. Network-removal errors can be tolerated by the script, so its
   completion message alone does not prove shutdown succeeded.
2. Verify all eight projects have no running containers and Plex still works.
   Preserve the stopped app datasets and verify a recoverable snapshot/backup
   of their state before any later restoration work.
3. **After merge**, run the normal full rollout to pull the retirement and
   refresh remaining services, including Traefik, Homepage, and Gatus:

   ```bash
   dccd-all
   ```

4. Verify Plex health, web access, library visibility, and playback; confirm
   all eight retired projects remain stopped and no retired routes, dashboard
   entries, or monitoring checks remain. Confirm the datasets, media/download
   files, accounts, groups, and ownership are unchanged.
5. Remove **only the eight retired TrueNAS Custom App registrations**, after
   their containers are stopped. Do not select any storage/volume deletion
   option or remove datasets, accounts, or groups. Leave Plex and shared
   infrastructure registrations intact. Resume coordinated automation after
   verification.

<!-- dprint-ignore -->
!!! warning "No storage cleanup"
    Do not destroy datasets, delete media/download files, remove accounts or
    groups, or reassign reserved IDs. Do not run blanket Docker prune or volume
    cleanup commands. Empty retained dataset mount directories are intentional,
    not abandoned storage to remove.
    Do not remove `_bootstrap`, its SOPS/DDNS/egress configuration, or its
    shared networks/connectivity. `arr-egress-init` still validates egress
    and creates networks needed by active Dawarich and IoT services;
    `content-init` still prepares the shared media tree. See the
    [retained bootstrap requirements](ARCHITECTURE.md#retired-arr-stack).

### Automatic Cleanup Alternative

If the pre-merge shutdown is missed, the first normal post-merge DCCD pull can
perform teardown: `dccd.sh` records the Compose paths before pulling, then
`cleanup_orphaned_projects` calls `remove_compose_project` for deleted Compose
files. This is an in-memory path inventory, **not a ZFS snapshot**.
TrueNAS project names use `ix-<app>`.

Label-based cleanup stops containers and removes them with `docker rm -f`
**without `-v`**, then attempts removal of project-labeled networks. It does
not delete datasets, volumes, accounts, or groups. A network can remain while
the old Traefik container is still attached; the full rollout removes those
obsolete attachments. Do not use blanket pruning to resolve a leftover
network, and do not treat network cleanup success as proof of app shutdown.
The retained bootstrap networks are not orphaned retired-app networks and must
not be removed as part of this cleanup.

This detection depends on DCCD seeing the old Compose paths before its pull.
A separate Git-only pull may bypass it; use the targeted `dccd-down` fallback
and the same verification steps if files are already gone. Retained directories
without Compose files are skipped during normal deployment. The alternative
does not replace the operator's checks or removal of stopped Custom App
registrations.

### Restore Without Rolling Back the Repository

Use last active commit `f73f9a451a9efb9f501f1019fc22c8e088302cb5`
as a reference on a **new branch from current main**, not as the production
checkout or a whole-repository reset/revert.

1. Inspect that commit's `services/<app>/` directory and service README.
   Selectively restore the desired app's tracked files from that commit into
   the new branch. Git restores configuration, not the retained runtime data.
2. Verify the retained bootstrap networks/egress validation, then selectively
   reintroduce removed dependencies: Traefik networks and middleware, DNS records,
   dashboard/monitoring integration, and any provisioning entries. Do not
   overwrite current shared files with their historical versions.
3. Restore service documentation, its MkDocs symlink/navigation entry, and
   active inventories in the same reviewed change. Reuse the reserved
   identities; Prowlarr and Spottarr were the only retired apps enrolled in
   `truenas-apps.json`. Other retired apps require their original manual
   account model, not new helper enrollment or replacement IDs.
4. Check current image support, security updates, data-schema compatibility,
   and API/Usenet/indexer credentials before enabling anything. Retain the
   SOPS-encrypted files and required age keys; decrypt only on the deployment
   host through the normal workflow, never into Git.
5. Verify the existing datasets are mounted at their original paths, preserve
   ownership and group memberships, and take a protective snapshot before
   startup can migrate state. Restore from backups only if needed; do not
   overwrite retained data merely to match the old Git revision.
6. Recreate only the desired Custom Apps with their reviewed Compose includes,
   provision shared network dependencies before dependent stacks/Traefik,
   and validate app functionality and Plex access after rollout.
