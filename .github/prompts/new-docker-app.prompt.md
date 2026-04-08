---
agent: 'agent'
description: 'Add a new Docker Compose app to the TrueNAS Apps repository following repo conventions.'
argument-hint: 'Paste the existing compose YAML or describe the app to add'
---

Implement the app described below as a new stack in this repository.

Requirements:

- Use other apps in `services/<app>` as a foundation and implement it with best practices and architecture described in [ARCHITECTURE.md](../../docs/ARCHITECTURE.md).
- Determine the correct PUID/PGID model for this app (media consumer, media producer, photos, or general — see the architecture doc).
- If a new shared PGID group is needed, create the corresponding env file in `services/shared/env/`.
- Every container must have a healthcheck. If the image is scratch-based (no shell), document why a healthcheck cannot be added.
- Configure Traefik labels with the appropriate middleware chain (`chain-auth@file`, `chain-no-auth@file`, etc.). Add a no-auth router only when the app cannot support OAuth/SSO (e.g. mobile-only apps).
- Do **not** add Gatus bypass routers — Gatus uses its own monitoring configuration.
- Add the app's frontend network to the Traefik compose file (`services/traefik/compose.yaml`).
- Add the app's subdomain(s) to `services/adguard/config/unbound/a-records.conf`, pointing to the correct `${IP_*}` variable for the server it runs on (e.g. `${IP_SVLNAS}` for NAS-hosted apps). If unsure what host, ask! Keep entries alphabetically sorted within the Internal or External section as appropriate.
- Validate the compose file by running `docker compose config` in the app directory.
- Update `README.md`: add the app to the Apps table and the dataset list.
- Update `docs/ARCHITECTURE.md`: add init container table entries, shared env entries, or new access model sections as needed.
- Create a `secret.sops.env` template listing every secret variable the app requires, then encrypt it in-place with `sops -e -i $(full-path)/secret.sops.env`.
- Output a summary table of all secrets/variables that need to be populated in `secret.sops.env`.
- Document any manual steps required on the TrueNAS host (creating groups, users, dataset ACLs, etc.).
