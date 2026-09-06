---
agent: 'agent'
description: 'Add a new Docker Compose app to the TrueNAS Apps repository following repo conventions.'
argument-hint: 'Paste the existing compose YAML or describe the app to add'
---

Implement the app described below as a new stack in this repository.

Requirements:

- Use other apps in `services/<app>` as a foundation and implement it with best practices described in [ARCHITECTURE.md](../../docs/ARCHITECTURE.md) (compose patterns) and [INFRASTRUCTURE.md](../../docs/INFRASTRUCTURE.md) (UID/GID, storage, multi-server).
- Determine the correct PUID/PGID model for this app (media consumer, media producer, photos, or general — see [INFRASTRUCTURE.md](../../docs/INFRASTRUCTURE.md)).
- If a new shared PGID group is needed, create the corresponding env file in `services/shared/env/`.
- Every container must have a healthcheck. If the image is scratch-based (no shell), document why a healthcheck cannot be added.
- Configure Traefik labels with the appropriate middleware chain (`chain-auth@file`, `chain-no-auth@file`, etc.). Add a no-auth router only when the app cannot support OAuth/SSO (e.g. mobile-only apps).
- Do **not** add Gatus bypass routers — Gatus uses its own monitoring configuration.
- Add the app's frontend network to the Traefik compose file (`services/traefik/compose.yaml`).
- Add the app's subdomain(s) to `services/adguard/config/unbound/a-records.conf`, pointing to the correct `${IP_*}` variable for the server it runs on (e.g. `${IP_SVLNAS}` for NAS-hosted apps). If unsure what host, ask! Keep entries alphabetically sorted within the Internal or External section as appropriate.
- Validate the compose file by running `docker compose config` in the app directory.
- Update `README.md`: add the app to the Apps table and the dataset list.
- Update `docs/ARCHITECTURE.md`: add init container table entries, shared env entries, or new access model sections as needed.
- Update `docs/INFRASTRUCTURE.md`: add UID/GID table entries, shared purpose group entries, or storage sections as needed.
- Create `services/<app>/secret.sops.env` with every required variable, set random variables to the literal `GENERATE`, and encrypt the sentinels in-place before running the helper.
- Prefer SOPS-native `SOPS_AGE_KEY_CMD` with an unlocked, signed-in 1Password Desktop CLI integration; never invoke or print the `op read` result directly. Treat `SOPS_AGE_KEY_FILE` and standard key-file locations as optional fallbacks.
- With a usable SOPS age key, automatically run `bash scripts/generate-sops-secrets.sh services/<app>/secret.sops.env VARIABLE=BYTE_COUNT [VARIABLE=BYTE_COUNT ...]` for generated values only. Exclude user-supplied credentials and shared values.
- Treat the helper as generate-once bootstrap: replace only exact decrypted `GENERATE` values, preserve every existing non-sentinel value, and accept a successful no-op without rewriting the file.
- Never run the helper concurrently against the same file or use it for rotation; rotate manually with `sops edit`.
- Never commit `CHANGE_ME` placeholders for generated secrets.
- Output a summary table classifying each secret as generated, user-supplied, or shared without revealing its value.
- Document any manual steps required on the TrueNAS host (creating groups, users, dataset ACLs, etc.).
