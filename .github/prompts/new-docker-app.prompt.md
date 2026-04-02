---
agent: 'agent'
description: 'Add a new Docker Compose app to the TrueNAS Apps repository following repo conventions.'
argument-hint: 'Paste the existing compose YAML or describe the app to add'
---

Implement the app described below as a new stack in this repository.

Requirements:

- Use other apps in `src/<app>` as a foundation and implement it with best practices and architecture described in [ARCHITECTURE.md](../../docs/ARCHITECTURE.md).
- Determine the correct PUID/PGID model for this app (media consumer, media producer, photos, or general — see the architecture doc).
- If a new shared PGID group is needed, create the corresponding env file in `src/shared/env/`.
- Every container must have a healthcheck. If the image is scratch-based (no shell), document why a healthcheck cannot be added.
- Configure Traefik labels with the appropriate middleware chain (`chain-auth@file`, `chain-no-auth@file`, etc.). Add a no-auth router only when the app cannot support OAuth/SSO (e.g. mobile-only apps).
- Do **not** add Gatus bypass routers — Gatus uses its own monitoring configuration.
- Add the app's frontend network to the Traefik compose file (`src/traefik/compose.yaml`).
- Validate the compose file by running `docker compose config` in the app directory.
- Update `README.md`: add the app to the Apps table and the dataset list.
- Update `docs/ARCHITECTURE.md`: add init container table entries, shared env entries, or new access model sections as needed.
- Create a `secret.sops.env` template listing every secret variable the app requires (unencrypted — the user will encrypt it with SOPS).
- Output a summary table of all secrets/variables that need to be populated in `secret.sops.env`.
- Document any manual steps required on the TrueNAS host (creating groups, users, dataset ACLs, etc.).
