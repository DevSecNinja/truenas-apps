# Changelog

All notable changes to this project will be documented in this file.

## [0.13.1] - 2026-04-11

### Bug Fixes

- **aliases**: Enhance dccd-down function to support multiple app names and improved error handling ([`80b2930`](https://github.com/DevSecNinja/truenas-apps/commit/80b29309954649232d787887a0a58675ac1b078f))
- **adguard**: Reorder A records for improved clarity and organization ([`7975bde`](https://github.com/DevSecNinja/truenas-apps/commit/7975bde4f16e7f606f9a675cdb3d08f6a5a8db10))
- **dccd**: Enhance server mode handling and app filter validation ([`9b75568`](https://github.com/DevSecNinja/truenas-apps/commit/9b7556893b24455b5786bb29910c32e5cbaa9a3a))
- **traefik**: Add Cloudflare key with hadiscover zone permissions ([`070dbeb`](https://github.com/DevSecNinja/truenas-apps/commit/070dbeb0da9fed5d9c1ea6254b57a16ab0045d9d))
- **hadiscover**: Remove redundant healthcheck from hadiscover-api service ([`0e8aa34`](https://github.com/DevSecNinja/truenas-apps/commit/0e8aa34184fd7ba3f9dd91b9b667fe64d0093b57))
- **container**: Update image ghcr.io/devsecninja/hadiscover/backend ( 0.2.14 ➔ 0.2.16 ) ([`142c967`](https://github.com/DevSecNinja/truenas-apps/commit/142c967ba234523b765296aa1aebb736193a3871))
- **dccd**: Skip empty service directories in TrueNAS mode ([`e69b13f`](https://github.com/DevSecNinja/truenas-apps/commit/e69b13f6d31f7ce7dfd2c966be710be4affc0d52))
- Update AZURE_CLIENT_SECRET and sops metadata for consistency ([`a28b74d`](https://github.com/DevSecNinja/truenas-apps/commit/a28b74d2013a04e4636b5c44d54a04ae9179fa9c))
- Enforce read-only mounts for git-tracked config volumes to prevent runtime modifications ([`1a33ced`](https://github.com/DevSecNinja/truenas-apps/commit/1a33cedebd43010484fe3537b8c1634b55a3779b))
- Set config volume to read-only to enhance security ([`ec777b4`](https://github.com/DevSecNinja/truenas-apps/commit/ec777b45885224a76c568f3f4cca6080827b8a73))
- Clarify ownership requirements for git-tracked config directories in init container documentation ([`ada590b`](https://github.com/DevSecNinja/truenas-apps/commit/ada590bd092da86c3ef2a2c4dc340b46f69b80f0))
- Update forward auth address to use internal service URL because Treafik needs server-side reach to auth ([`0ef7c9c`](https://github.com/DevSecNinja/truenas-apps/commit/0ef7c9cb5560c1a041099e275e26618a2f794919))

### Features

- **dccd**: Reorder Traefik deployment to ensure it joins external networks last ([`d80cfa9`](https://github.com/DevSecNinja/truenas-apps/commit/d80cfa9c14c97f18c58e5175959c8fc195995a72))
- **hadiscover**: Add hadiscover service with initialization and API components ([`542a29d`](https://github.com/DevSecNinja/truenas-apps/commit/542a29d0f826f9941263eeb5d3be9271b5bbbfcd))
- **gatus**: Comment out DNS endpoint tests and add TODO for fixing internal and external resolution paths ([`a103737`](https://github.com/DevSecNinja/truenas-apps/commit/a1037371cb6bd55c59c495c8e78b35ed5d3446e9))
- **gatus**: Remove DNS resolver configuration from V60 endpoint - hope this fixes context deadline exceeded error ([`781ae16`](https://github.com/DevSecNinja/truenas-apps/commit/781ae16f4b1320499e7b459644168127a92beeb8))
- **adguard**: Exempt v60 subdomain from static zone for forward-zone resolution ([`1dae8f6`](https://github.com/DevSecNinja/truenas-apps/commit/1dae8f6b0f57d38d023de5ddeb7e20a9b90f7af3))
- **gatus**: Update HTTP status conditions for external endpoints ([`e63a9ad`](https://github.com/DevSecNinja/truenas-apps/commit/e63a9adec600a3ff9e46c6cffa4b13e46586289d))
- **adguard**: Add public IP variable for external access ([`e58c09e`](https://github.com/DevSecNinja/truenas-apps/commit/e58c09e2dd2147b0058f9fc5ff8ea3b899dcc758))
- **gatus**: Add DNS resolver configuration for external endpoints ([`12ee3c8`](https://github.com/DevSecNinja/truenas-apps/commit/12ee3c84283bce7b7eb023a801466e4e6a5ec561))
- **gatus**: Update endpoint conditions and add client redirect handling for external services ([`f39a0c1`](https://github.com/DevSecNinja/truenas-apps/commit/f39a0c125484b299d4230e91a46852a55331c47b))
- **gatus**: Update conditions and URLs for health checks in multiple services ([`974f09b`](https://github.com/DevSecNinja/truenas-apps/commit/974f09bbdd6810d70545eb54c42447aef428f5f9))
- **traefik**: Add monitoring entrypoints for unifi and unifi-guest services ([`9c24ae0`](https://github.com/DevSecNinja/truenas-apps/commit/9c24ae063d54ecb11d92bad7fd79b4e186f6d8d3))
- **services**: Add monitoring entrypoints for Gatus in multiple services ([`7ab1b1e`](https://github.com/DevSecNinja/truenas-apps/commit/7ab1b1e9b201b3076a4d61c59dce84b0dd26ee32))
- **aliases**: Enhance dccd-app to support multiple app deployments ([`9e025b3`](https://github.com/DevSecNinja/truenas-apps/commit/9e025b388c61c80adb64a33bd177dda98d589a24))
- **traefik**: Add entrypoints for multiple services to enhance routing ([`15b8cb7`](https://github.com/DevSecNinja/truenas-apps/commit/15b8cb739a940c337d86e0d6f1387606a0b7c1af))
- **traefik**: Add entrypoints for Dozzle, Drawio, and Echo Server routers ([`c2c84ed`](https://github.com/DevSecNinja/truenas-apps/commit/c2c84ed5ac059e04fadd847cebbb4e429e264f6a))
- **aliases**: Add cleaning functions for Docker containers, images, volumes, and networks ([`4df9438`](https://github.com/DevSecNinja/truenas-apps/commit/4df9438ddb68a8dc94182c00401bbc9c803d996e))
- Update Gatus URLs to use static IP for improved reliability across services ([`c2dcff9`](https://github.com/DevSecNinja/truenas-apps/commit/c2dcff9d91ed892a9f898ea1f1b2f07b1c287b4b))
- Update Gatus URLs to use static IP for improved reliability ([`22964ae`](https://github.com/DevSecNinja/truenas-apps/commit/22964aeec87dab438e6788a73075cfdabf1d5acf))
- **openspeedtest**: Retire OpenSpeedTest service ([`2cf043c`](https://github.com/DevSecNinja/truenas-apps/commit/2cf043cf9815dd60b0e293222ab1786140178189))
- **dccd**: Add app retirement mechanism with auto-cleanup ([`d137a22`](https://github.com/DevSecNinja/truenas-apps/commit/d137a2201c5e040994112d14042f9492a874d302))
- Add Gatus monitoring configuration for multiple services with specific headers ([`d9e67be`](https://github.com/DevSecNinja/truenas-apps/commit/d9e67bec9054b791b6650d785e9f93a349d60324))
- Add Gatus monitoring for various services with internal entrypoint configuration ([`c8d1932`](https://github.com/DevSecNinja/truenas-apps/commit/c8d1932cd095d5210026cda0dfc09617b5ed6c5c))
- Add COOKIE_NAME_PREFIX environment variable for server-specific cookie naming ([`e12361f`](https://github.com/DevSecNinja/truenas-apps/commit/e12361f41e933cfb5f4bdbeff858d497e0006cdd))
- Add option to update keys on existing encrypted files in generate-sops-rules script ([`572ecf6`](https://github.com/DevSecNinja/truenas-apps/commit/572ecf672a62075cae9d7276d4c2e0b451476442))
- Enhance secret management and server-specific configurations for traefik-forward-auth ([`a1f45d3`](https://github.com/DevSecNinja/truenas-apps/commit/a1f45d375f9b0d4955d61132ae749fe96cb87605))
- Update forward auth address to use domain variable for improved flexibility ([`48270ca`](https://github.com/DevSecNinja/truenas-apps/commit/48270ca126066c6d33261a4a39f7d8cc59f54bf0))
- Log total execution time in update_compose_files function ([`a733547`](https://github.com/DevSecNinja/truenas-apps/commit/a73354738282aa51b63c637a3be973a7cde93bef))
- Update endpoints for traefik-ext and adguard-ext with new conditions and URLs ([`a451162`](https://github.com/DevSecNinja/truenas-apps/commit/a4511620c2979abe3108b9b9b3154032da5ea7eb))
- Add svlazext A record and create compose override for AdGuard service ([`d25f770`](https://github.com/DevSecNinja/truenas-apps/commit/d25f7706606e43c87b206d34f22dad3f5dc73270))
- Refactor aliases.sh for improved environment detection and script execution ([`596b329`](https://github.com/DevSecNinja/truenas-apps/commit/596b3291ae58308592c6e2421d4527c009008cad))
- Add SVLAZEXT A record and update Gatus configuration for new endpoint ([`1d39eb2`](https://github.com/DevSecNinja/truenas-apps/commit/1d39eb2a4d6b03f299ef90d1c8b2317bcb8ade96))
- Configure static IP addresses for adguard services and update DNS settings ([`9d4236e`](https://github.com/DevSecNinja/truenas-apps/commit/9d4236e1de3070a2637721d509bfcd883fa5521c))
- Update autoMerge and packageRules for improved dependency management and security ([`d4cf421`](https://github.com/DevSecNinja/truenas-apps/commit/d4cf4219396411ccb0e19891bb1eab21553d602f))
- Enhance deployment logic to trigger updates on fresh servers with no running containers ([`06e84ab`](https://github.com/DevSecNinja/truenas-apps/commit/06e84ab47c98e56d8aa06b7e1d54537ffedf7d35))
- Update aliases.sh and dccd.sh for improved user instructions and ownership checks ([`2d8705c`](https://github.com/DevSecNinja/truenas-apps/commit/2d8705c1665d1bc03883c650d1527943e72e966d))
- **mise**: Update tool yq ( 4.45.4 ➔ 4.52.5 ) ([`fe6d279`](https://github.com/DevSecNinja/truenas-apps/commit/fe6d2792a8a384a6386cfc3807df65b37180923f))
- **mise**: Update tool pipx:check-jsonschema ( 0.33.0 ➔ 0.37.1 ) ([`4cf3edb`](https://github.com/DevSecNinja/truenas-apps/commit/4cf3edb445e7b8331182b50ed26a76cd8bc7cc2a))
- Update devcontainer configuration and add post-create script for environment setup ([`b1f12d6`](https://github.com/DevSecNinja/truenas-apps/commit/b1f12d6c8270344fbb7f5685a1f44a99aa5e90a5))
- Update encrypted secrets for various services in the environment configuration files to include new hosts ([`3b8f72f`](https://github.com/DevSecNinja/truenas-apps/commit/3b8f72f65783d968f0833bfd6d03c066e6c542d0))
- Add SOPS_AGE_KEY_FILE to remote environment in devcontainer configuration ([`18b67a4`](https://github.com/DevSecNinja/truenas-apps/commit/18b67a43b92e5eb8aa6d765be32b150b94248a44))
- Enhance SOPS rules generation and update documentation ([`5513590`](https://github.com/DevSecNinja/truenas-apps/commit/55135908b5ec088a35ece146398cee9905341657))
- Update multi-server deployment documentation and validation logic ([`c21dd18`](https://github.com/DevSecNinja/truenas-apps/commit/c21dd18a542241fe45b324626656d9dd83e7b0d2))
- Update .gitignore to ignore all key files ([`40b8b8f`](https://github.com/DevSecNinja/truenas-apps/commit/40b8b8f2925736ae45b6a2c2ef0759e7b04dfee5))
- Add age tool configuration and update mise.lock ([`6179948`](https://github.com/DevSecNinja/truenas-apps/commit/617994820ceee04bf6317d6d8ffef5e660c855d1))
- Add multi-server deployment support ([`d691bf5`](https://github.com/DevSecNinja/truenas-apps/commit/d691bf56db556c64e8601184e5a08a260bd1f290))
- **settings**: Add git post-commit command to sync changes ([`ee22d32`](https://github.com/DevSecNinja/truenas-apps/commit/ee22d326c8540524637333abaac7b5d7dc8e5852))
- **mcp**: Update GitHub MCP server configuration and remove deprecated settings ([`b50dc77`](https://github.com/DevSecNinja/truenas-apps/commit/b50dc7744f9a373e2374b0b5fda522194d402f1f))
- **CODEOWNERS**: Add default code owner for pull request reviews ([`dee7f43`](https://github.com/DevSecNinja/truenas-apps/commit/dee7f430735e97579253f83179bc21e9f55cfad9))
- **mcp**: Add microsoft-learn server configuration ([`d140599`](https://github.com/DevSecNinja/truenas-apps/commit/d140599e803da0596854f6f239d04a4948dc50b6))

### Refactoring

- Update init container guidelines to prevent chown on git-tracked directories and improve ownership checks ([`1f040d2`](https://github.com/DevSecNinja/truenas-apps/commit/1f040d2ffdf654aaec1aab43ce83e2ca1e9a06bb))
- Streamline alerting and endpoint configurations by removing unused client settings and consolidating defaults ([`3d3b092`](https://github.com/DevSecNinja/truenas-apps/commit/3d3b092aeefbb3447ed979ce00a8a434adce20fb))

## [0.13.0] - 2026-04-09

### Bug Fixes

- **container**: Update image docker.io/jgraph/drawio ( 29.6.5 ➔ 29.6.10 ) ([`bb1c248`](https://github.com/DevSecNinja/truenas-apps/commit/bb1c2489432155d6384e99688fc20453bf1504be))
- **container**: Update image ghcr.io/alexta69/metube ( 2026.04.03 ➔ 2026.04.09 ) ([`e488c74`](https://github.com/DevSecNinja/truenas-apps/commit/e488c743ee9c1f5c0e1890069c5326ed3da3c2b7))
- **README**: Reorder app list and organization in services section ([`213dc49`](https://github.com/DevSecNinja/truenas-apps/commit/213dc498208837098b109e4d107472570ab8a417))

### Documentation

- **release**: Update prerequisites and add instructions for syncing before release ([`9c7aa37`](https://github.com/DevSecNinja/truenas-apps/commit/9c7aa37486ca2d6a7ff69a1eb417d3dd6c7c2b34))

### Features

- **outline**: Disable email login and update SMTP security settings ([`a0c906a`](https://github.com/DevSecNinja/truenas-apps/commit/a0c906ad5c88aff520ee82a792fc31fe8154b0ec))
- **home-assistant**: Add template files for configuration, automations, scripts, and scenes ([`7a14392`](https://github.com/DevSecNinja/truenas-apps/commit/7a14392ecb9823b43239d5b0d5c8ed2300271ccf))
- **container**: Update pgautoupgrade image to version 18.3-alpine ([`4c07223`](https://github.com/DevSecNinja/truenas-apps/commit/4c072238744b8bd8c270ee25ba87feeec8be1c0d))
- **container**: Update image ghcr.io/meeb/tubesync ( v0.16.3 ➔ v0.17.1 ) ([`be53613`](https://github.com/DevSecNinja/truenas-apps/commit/be536130e3e8127767db475a4065206d07940db1))
- **container**: Update image docker.io/library/postgres ( 16.10 ➔ 18.3 ) ([`c79c6b9`](https://github.com/DevSecNinja/truenas-apps/commit/c79c6b97ed0c832227e655b849ac091d41abbb2f))
- **container**: Update image docker.io/outlinewiki/outline ( 0.87.4 ➔ 1.6.1 ) ([`103ae64`](https://github.com/DevSecNinja/truenas-apps/commit/103ae64686b87778dfbb7c10b7644ad0d2f5b67d))
- **container**: Update image docker.io/pgautoupgrade/pgautoupgrade ( 16 ➔ 17 ) ([`3832bb9`](https://github.com/DevSecNinja/truenas-apps/commit/3832bb9f7a78d397bd8f7e3c47fca2c2ee86afa9))
- **home-assistant**: Add initialization service and base configuration for first deploy ([`4eea5ef`](https://github.com/DevSecNinja/truenas-apps/commit/4eea5ef15d1c38822e48ae9fc73e0ea54f458868))
- **container**: Update image docker.io/library/redis ( 8.2.1 ➔ 8.6.2 ) ([`da122eb`](https://github.com/DevSecNinja/truenas-apps/commit/da122eb0ae77876ae5e14ba563192414ed48e223))
- **dccd**: Ensure decryption occurs in decrypt-only mode regardless of new commits ([`d58e998`](https://github.com/DevSecNinja/truenas-apps/commit/d58e9982ccebf9aad76c7a57e611f15310742f5b))
- **outline**: Update Redis configuration to improve session handling and security ([`e9ae85a`](https://github.com/DevSecNinja/truenas-apps/commit/e9ae85aaf785735f75ee7ba9a84d0c6a93ff0277))
- **dccd**: Enhance decrypt-only mode to perform a git sync before decrypt ([`8e8af2a`](https://github.com/DevSecNinja/truenas-apps/commit/8e8af2a5e597351b2af98c56ae6864f04abed032))
- **dccd**: Add decrypt-only option for SOPS-encrypted env files ([`ffb739e`](https://github.com/DevSecNinja/truenas-apps/commit/ffb739e52df0f963e5274d409c05a90e837858ba))
- **dccd**: Add validation for Docker Compose files before deployment ([`aac1f22`](https://github.com/DevSecNinja/truenas-apps/commit/aac1f22c00051248986e13be485ff275eca8c560))
- **outline**: Add Outline service with initial configuration and secrets ([`3946bf1`](https://github.com/DevSecNinja/truenas-apps/commit/3946bf12a30407c19a8b135ac3289f4f9a2f3c72))
- **home-assistant**: Update service configuration to support s6-overlay and DHCP watcher integration ([`a3ac6b8`](https://github.com/DevSecNinja/truenas-apps/commit/a3ac6b8f6cc6a05d2013ee72afd02d2b20e8a9d6))
- **openspeedtest**: Add OpenSpeedTest-specific middleware and update Traefik configuration ([`a26fa84`](https://github.com/DevSecNinja/truenas-apps/commit/a26fa8490b2b5ed1640f13b50ef71f91c13de678))
- **home-assistant**: Add Home Assistant service and update configurations ([`e32ff03`](https://github.com/DevSecNinja/truenas-apps/commit/e32ff0329b8e1f23b4e788360e6f573e34b7a4f3))

### Miscellaneous

- **version**: V0.13.0 ([`ae7a4c0`](https://github.com/DevSecNinja/truenas-apps/commit/ae7a4c0eecbce4f21e7e332ddbebce670b06ade1))

## [0.12.0] - 2026-04-08

### Bug Fixes

- **prompt**: Clarify instructions for adding app subdomains in A records ([`2ddd46a`](https://github.com/DevSecNinja/truenas-apps/commit/2ddd46a5ba9e20f452ee56739bc59484b38e75b6))
- **adguard**: Update A records for draw, excalidraw, and speedtest to point to SVLNAS ([`72e01c3`](https://github.com/DevSecNinja/truenas-apps/commit/72e01c36da6bf72e517944d527de14b412662fdf))
- **excalidraw**: Update healthcheck command from wget to curl for improved reliability ([`225c1a3`](https://github.com/DevSecNinja/truenas-apps/commit/225c1a32fbd52865b56a12fccb0c019020d07388))

### Documentation

- Add guide for writing Conventional Commit messages and creating releases ([`088a3e0`](https://github.com/DevSecNinja/truenas-apps/commit/088a3e00b93eeed19ce334981af103f5218aedb9))

### Features

- **container**: Update image docker.io/jgraph/drawio ( 29.3.6 ➔ 29.6.5 ) ([`b056b96`](https://github.com/DevSecNinja/truenas-apps/commit/b056b96204a88d59a527c3f5c4e34c68c752c0a3))
- **traefik**: Add frontend services for Excalidraw, OpenSpeedTest, Draw.io, and TubeSync ([`441f1a0`](https://github.com/DevSecNinja/truenas-apps/commit/441f1a0b4f48ea11ea3a145ccec48fee42481d40))
- **openspeedtest**: Add OpenSpeedTest service configuration and secrets management ([`f5a22f1`](https://github.com/DevSecNinja/truenas-apps/commit/f5a22f1a85f6156b09b98be32fdda35c1faab199))
- **excalidraw**: Add Excalidraw service configuration and secrets management ([`19f9a1b`](https://github.com/DevSecNinja/truenas-apps/commit/19f9a1be962dcb742a67ee674439926df13da97a))
- **drawio**: Add Draw.io service configuration and secrets management ([`80dc4c7`](https://github.com/DevSecNinja/truenas-apps/commit/80dc4c7bb2f57b5fd4cf668c2417b369cd9e98e6))
- **tubesync**: Add new service configuration and secrets management ([`a0cb6ae`](https://github.com/DevSecNinja/truenas-apps/commit/a0cb6ae0037144abd36ba9410898d2ac9655f34f))

### Miscellaneous

- **version**: V0.12.0 ([`38a1d9f`](https://github.com/DevSecNinja/truenas-apps/commit/38a1d9fca6fd1d3ff21b9cf2576a176cee3fa8e8))

## [0.11.0] - 2026-04-08

### Bug Fixes

- **cog**: Limit changelog to v0.10.0 onwards ([`eb165bd`](https://github.com/DevSecNinja/truenas-apps/commit/eb165bd5557d4834fc78b75c1e2fddc049621d42))
- **aliases**: Update dps alias to include sorting of container health status ([`d90a252`](https://github.com/DevSecNinja/truenas-apps/commit/d90a25234aef07f6c7813b32c0676c85f6da72ee))
- **compose**: Add arr-stack-backend service to the arr-egress network configuration ([`69af754`](https://github.com/DevSecNinja/truenas-apps/commit/69af754c7685781995a8083deeaf50cb8701ee0f))
- **arr**: Simplify arr stack networking ([`0ae6489`](https://github.com/DevSecNinja/truenas-apps/commit/0ae6489dbf0b4f865db13e393641993722826023))
- **compose**: Update arr-stack-backend network configuration to use bridge driver and set internal access ([`25352d2`](https://github.com/DevSecNinja/truenas-apps/commit/25352d2283dbd68c6710e7d92992b73da0fd9530))

### CI/CD

- Add automated release pipeline with git-cliff and cog ([`ad21f02`](https://github.com/DevSecNinja/truenas-apps/commit/ad21f0270f2d56d78927b88004b438800b5f0935))

### Features

- **pre-commit**: Add sops-encryption-check command to validate SOPS encryption ([`3ee414d`](https://github.com/DevSecNinja/truenas-apps/commit/3ee414d14dbf0c067142c6613eb11c6f0354e2c8))
- **arr**: Add the rest of the arr stack (excl. Traefik networks) ([`c9f69b0`](https://github.com/DevSecNinja/truenas-apps/commit/c9f69b08eed8fdcbb6ad3bc6911805c94ac442ef))

### Miscellaneous

- **version**: V0.11.0 ([`c50266d`](https://github.com/DevSecNinja/truenas-apps/commit/c50266d6950fd436f8c5775aadd76d3b343b423d))

## [0.10.0] - 2026-04-07

### Bug Fixes

- **renovate**: Refine update timing policy for GitHub Actions and clarify auto-merge requirements ([`74ea41c`](https://github.com/DevSecNinja/truenas-apps/commit/74ea41c7e52ec065ab53aff597f8c08bff4fb3c9))
- **renovate**: Update package rules for dependency management and improve configuration clarity ([`8f3990b`](https://github.com/DevSecNinja/truenas-apps/commit/8f3990b7f08c1a35497136d89f11c96c909dc3c9))
- **mise**: Add cocogitto tool and update version to 7.0.0 in configuration ([`c38aa9f`](https://github.com/DevSecNinja/truenas-apps/commit/c38aa9f41fea5bbe0b235fc17bcfa59a67c9e1db))
- **database**: Update gatus-db restart policy to on-failure with max attempts for improved stability ([`a275c43`](https://github.com/DevSecNinja/truenas-apps/commit/a275c43ed32cdb70498607f6f303833b501274a9))
- **services**: Update restart policy to on-failure with max attempts for improved stability ([`eda58e2`](https://github.com/DevSecNinja/truenas-apps/commit/eda58e2f602500e4b542444d843304b8a2e77419))
- **immich**: Update mobile app endpoint and OAuth configuration for improved authentication flow ([`686377f`](https://github.com/DevSecNinja/truenas-apps/commit/686377f719d87093caa7470552398dabb41c015d))
- **dccd**: Enhance Gatus reporting with DNS resolution and improved error logging ([`dfe1c61`](https://github.com/DevSecNinja/truenas-apps/commit/dfe1c6124b0d2b6260a633302831cbe7fe309c30))
- **echo-server,metube**: Update restart policy to on-failure with max attempts ([`c53333d`](https://github.com/DevSecNinja/truenas-apps/commit/c53333d4c468a95f15d152ecb68b9bc830e3dc63))
- **gatus**: Update alert configurations to enable custom alert types and correct DNS endpoint URLs ([`12f7af3`](https://github.com/DevSecNinja/truenas-apps/commit/12f7af3bfc9fb4e7c64ab739f43172ef527ad6d4))
- **immich**: Add App Roles configuration for admin/user assignment via Entra token ([`e64d174`](https://github.com/DevSecNinja/truenas-apps/commit/e64d1745cd0eb8143ca8e76df8bd4e454e680e17))
- **immich**: Update roleClaim in OAuth configuration from 'immich_role' to 'roles' ([`85c468a`](https://github.com/DevSecNinja/truenas-apps/commit/85c468a09cf7d806d99fcada0f71114b225c4a33))
- **immich**: Enable autoLaunch for OAuth and disable password login ([`a7b103e`](https://github.com/DevSecNinja/truenas-apps/commit/a7b103ebbc14b099dea29a8778b62aa10826d26a))
- **gatus**: Update DNS server references to use IP_ROUTER for endpoint configurations ([`dfd6888`](https://github.com/DevSecNinja/truenas-apps/commit/dfd68881b55d2c1f785606a99a2df4503a446c40))
- **dccd**: Enhance Gatus DNS server handling with fallback mechanism ([`572571d`](https://github.com/DevSecNinja/truenas-apps/commit/572571d2869f65561073618096f26b7fdb58d2bf))
- **immich**: Streamline ownership handling in Docker Compose and update README for storage layout ([`0f34ffa`](https://github.com/DevSecNinja/truenas-apps/commit/0f34ffa9ce61db71e31692562b44372c3c628051))
- **immich**: Improve ownership handling in init script and documentation ([`eb04c20`](https://github.com/DevSecNinja/truenas-apps/commit/eb04c2018455b8a5c011efa455e1fe12f62740d9))
- **immich**: Correct comment formatting in configuration template ([`72957a5`](https://github.com/DevSecNinja/truenas-apps/commit/72957a562d54a5344cb34c341e258f1b6e7602f0))
- **gatus**: Optimize config file copy to avoid unnecessary overwrites ([`47ea6ff`](https://github.com/DevSecNinja/truenas-apps/commit/47ea6ff711c007035d4b832a49f79bdb25587206))
- **radarr**: Correct environment variable name for stable MAC address in compose file ([`c32bbe5`](https://github.com/DevSecNinja/truenas-apps/commit/c32bbe538c711d9f767f0c1d07eb5a1b95705a5d))
- **adguard**: Disable unbound remote control for now ([`85ef623`](https://github.com/DevSecNinja/truenas-apps/commit/85ef62360a32c69db469e307a9c3590939740e47))
- **adguard**: Update A records to point to SVLNAS for various services ([`7f0d59d`](https://github.com/DevSecNinja/truenas-apps/commit/7f0d59da15ee29a983c4bbcf6e010746780d0e2a))
- **plex**: Update setup instructions for enabling Remote Access and specifying public port ([`fdc3709`](https://github.com/DevSecNinja/truenas-apps/commit/fdc37099c375f89e74ef3aebeea17c01eda69e76))
- **dccd**: Remove unnecessary ownership restoration code in update_compose_files function ([`36c3af1`](https://github.com/DevSecNinja/truenas-apps/commit/36c3af140de2d6120d7953884611ad4d4153983c))
- **adguard**: Add Cloudflare DNS addresses to AdGuard configuration ([`d18518e`](https://github.com/DevSecNinja/truenas-apps/commit/d18518e3dd5b72a6eb68019fbe0fedb8cdab98e1))
- **plex**: Update backup directory configuration in Plex settings and volume mounts ([`a7ab321`](https://github.com/DevSecNinja/truenas-apps/commit/a7ab32142e441da6198c093b10ef8efe28b8e823))
- **dccd**: Improve git update logic with concise logging and quiet checkout ([`ec6d4d1`](https://github.com/DevSecNinja/truenas-apps/commit/ec6d4d1dc07c5811c093245ad038ceb5f4a9a1b8))
- **plex**: Simplify media mount points by consolidating into a single directory ([`0b1b4e3`](https://github.com/DevSecNinja/truenas-apps/commit/0b1b4e3838334fa3de080c9cb0a20a9e34893669))
- **dccd**: Enhance deployment logic for bootstrap projects to run in foreground ([`357920e`](https://github.com/DevSecNinja/truenas-apps/commit/357920e3b46fb99f89c0c5e555d375a83a77702e))
- **dccd**: Adjust app name handling to remove leading underscores for TrueNAS compatibility ([`c79e546`](https://github.com/DevSecNinja/truenas-apps/commit/c79e546b42c16dab199d3f034cee0fe330eaa234))
- **immich**: Re-enable hardware acceleration for transcoding service ([`0060b9f`](https://github.com/DevSecNinja/truenas-apps/commit/0060b9f44185610762e1339b50eef88b536f2f05))
- **architecture**: Update group permissions and references for media datasets ([`137ce97`](https://github.com/DevSecNinja/truenas-apps/commit/137ce9724009f34787459545f9178b0fe5ee0d02))
- **gatus**: Update external endpoint configuration to use public DNS resolver and add certificate expiration check ([`804fb3b`](https://github.com/DevSecNinja/truenas-apps/commit/804fb3b94c4a7e1ccd43fdc8ecaa3b086bcafb61))
- **gatus**: Update DNS resolver timeout and add IP_DNS_SERVER_1 variable ([`8d30f3b`](https://github.com/DevSecNinja/truenas-apps/commit/8d30f3b5652b86250388c34138f6b29ff128402f))
- **adguard**: Add forward-tls-upstream to DDNS and V60 forward zones ([`c8084f0`](https://github.com/DevSecNinja/truenas-apps/commit/c8084f0c1897c1d183e95cd6628a7635167b4c0e))
- **devcontainer**: Remove auth sock ([`3d513a1`](https://github.com/DevSecNinja/truenas-apps/commit/3d513a1ed0615c27cc56b68fe4a8b9527b9c27e8))
- **devcontainer**: Add SSH_AUTH_SOCK to remote environment and update mounts ([`854cd0d`](https://github.com/DevSecNinja/truenas-apps/commit/854cd0d28815cc3d12fec3306985c3777cdfbd32))
- **immich**: Update Postgres volume path for new postgresql ([`1f73bc7`](https://github.com/DevSecNinja/truenas-apps/commit/1f73bc719727b8506a368227b21a6d593d8225f4))
- **adguard**: Revert & comment out Cloudflare DNS addresses in fallback and forward zones ([`156abbc`](https://github.com/DevSecNinja/truenas-apps/commit/156abbc272ae69cab263979227ae50e61e669abe))
- **adguard**: Add Cloudflare DNS addresses to forward zones configuration to improve stability ([`4167d9f`](https://github.com/DevSecNinja/truenas-apps/commit/4167d9f6a4fe72957d79fbda52f6ec6860f32604))
- **dccd**: Comment out ownership restoration logic as it's handled by init containers ([`a1e6596`](https://github.com/DevSecNinja/truenas-apps/commit/a1e65967de1e14cbf7d1ec470a76d14a2ce76865))

### Documentation

- **architecture**: Add commit message convention section with guidelines ([`a0b37db`](https://github.com/DevSecNinja/truenas-apps/commit/a0b37db2345d5f86a736dd24983c84f719fb509e))

### Features

- **renovate**: Add automerge label and update auto-merge rules for GitHub Actions ([`adf21be`](https://github.com/DevSecNinja/truenas-apps/commit/adf21be1af2ca1b0bf01dbfe5f1b10489ca6c3d1))
- **renovate**: Add package rules for dependency management and custom versioning ([`e553a24`](https://github.com/DevSecNinja/truenas-apps/commit/e553a240385622a0359080f2f77b3be5baff9451))
- **renovate**: Add new configuration files for Renovate, including autoMerge, customManagers, groups, labels, and semanticCommits ([`96150de`](https://github.com/DevSecNinja/truenas-apps/commit/96150de08d2bd809e24a5b7e488ec7a676e5f15f))
- **adguard**: Add A record for photos-noauth service ([`7040d78`](https://github.com/DevSecNinja/truenas-apps/commit/7040d7846c37b86e11db4b920e7c0c8b89e5b4da))
- **immich**: Add initial README, configuration files, and envsubst script for deployment ([`57b3259`](https://github.com/DevSecNinja/truenas-apps/commit/57b3259c533a1f3de10dfa1f487160a61f0dc864))
- **dccd**: Add GATUS_DNS_SERVER option for custom DNS in Gatus curl calls ([`e45acd4`](https://github.com/DevSecNinja/truenas-apps/commit/e45acd4f4c78d141e4abf3b50d0119891e32576e))
- **gatus**: Add custom alert configuration with webhook support ([`6f95f4e`](https://github.com/DevSecNinja/truenas-apps/commit/6f95f4eaeb938b60d93f1261b7cc35547dae454e))
- **aliases**: Add alias for viewing recent dccd cron job logs ([`3c9a261`](https://github.com/DevSecNinja/truenas-apps/commit/3c9a261a955e7a0d992bda0ba71845cd655a2e46))
- **gatus**: Enable /events stream access for gatus-sidecar in compose file ([`5aaedc5`](https://github.com/DevSecNinja/truenas-apps/commit/5aaedc5ab7ee60b5e0b5df4444a574452d230f3e))
- **radarr**: Add stable MAC address variables for Radarr service configuration ([`38c729c`](https://github.com/DevSecNinja/truenas-apps/commit/38c729c72d2c4431198a35ba12492e40a1f1a483))
- **adguard**: Update A records for services to point to SVLNAS ([`d84965e`](https://github.com/DevSecNinja/truenas-apps/commit/d84965ed126a350e7345dd23091073e4aa22d786))
- **aliases**: Update docker commands for stack management and add ddown alias ([`b9b2660`](https://github.com/DevSecNinja/truenas-apps/commit/b9b266074c93e62979d144685451fc08e2aa067a))
- **radarr**: Update VLAN IP variables for Radarr service configuration ([`f53fa2e`](https://github.com/DevSecNinja/truenas-apps/commit/f53fa2e0c74b731305deb8d5530a4a8dfc405020))
- **radarr**: Add Radarr service to documentation and configuration ([`3fb46c2`](https://github.com/DevSecNinja/truenas-apps/commit/3fb46c29006b8a9604008f89983354ec34ec814e))
- **adguard**: Add split-horizon configuration for local-domain queries ([`5df02f7`](https://github.com/DevSecNinja/truenas-apps/commit/5df02f725aa7eefe9a8c09935338f106d39eb53a))
- **adguard**: Update DNS configuration to enhance IPv6 support and streamline fallback DNS entries ([`2e4a2df`](https://github.com/DevSecNinja/truenas-apps/commit/2e4a2df0865417fc8821a016768972193324ba59))
- **radarr**: Dhcp driver not available for init container ([`4fd2ea0`](https://github.com/DevSecNinja/truenas-apps/commit/4fd2ea08b29655d3b4343f74db138526198976f0))
- **radarr**: Update radarr-init container to validate VLAN 70 egress and add DDNS_DOMAIN support ([`075bd28`](https://github.com/DevSecNinja/truenas-apps/commit/075bd285aef69b724261d786f9bc06971afc5a5b))
- **dccd**: Update log message to indicate suppressed output for one-shot deployment ([`a7b1325`](https://github.com/DevSecNinja/truenas-apps/commit/a7b1325c1551a3c604b4827e09e6f69bcc2cf5b0))
- **dccd**: Suppress output for one-shot container deployment logs ([`495bd9b`](https://github.com/DevSecNinja/truenas-apps/commit/495bd9b2ab3728907e68b8223113ea37980a8c94))
- **dccd**: Revert back to one-shot bootstrap logic from 357920e ([`05a79cc`](https://github.com/DevSecNinja/truenas-apps/commit/05a79ccaf0c8df3ceb10ccc9ae5c436c209eeb93))
- **dccd**: Enhance ownership check for root-owned files and provide manual fix instructions ([`f424aae`](https://github.com/DevSecNinja/truenas-apps/commit/f424aaed8ab87311a1ca2d799fd396fd8081bcfa))
- **radarr**: Add initial Radarr service configuration and environment secrets ([`cacaff6`](https://github.com/DevSecNinja/truenas-apps/commit/cacaff673f3b77cc0867b8a195315ee337c7ac82))
- **dccd**: Enhance redeploy function to explicitly wait for specified services ([`570df30`](https://github.com/DevSecNinja/truenas-apps/commit/570df30b4853e93fbd7f968e5e50465756d3f7c9))
- **dccd**: Update user instructions and enforce non-root execution for improved security ([`b7f0933`](https://github.com/DevSecNinja/truenas-apps/commit/b7f093345c58a0e618cc76eb8d05ed2f05eb212a))
- **aliases**: Remove sudo from ddeploy and dccd aliases for improved usability ([`020fc29`](https://github.com/DevSecNinja/truenas-apps/commit/020fc29fbc64799c0bbcf060b4674ab920c66ce3))
- **architecture**: Update dataset layout for downloads and media organization ([`7b62ed6`](https://github.com/DevSecNinja/truenas-apps/commit/7b62ed622ed38e35efe5fb85d38ed25d5da67621))
- **bootstrap**: Expand downloads directory structure for torrents and usenet ([`969e0b2`](https://github.com/DevSecNinja/truenas-apps/commit/969e0b27e853551728a3abeb70df4747f6de37b9))
- **aliases**: Add alias to show resource usage of all containers ([`faedd6d`](https://github.com/DevSecNinja/truenas-apps/commit/faedd6de74e71a7e7bcb8da3880ffb281d639382))
- **unifi**: Run guest portal on 443 ([`e8c195f`](https://github.com/DevSecNinja/truenas-apps/commit/e8c195f6558114d2c1b90f8a10ba9f74f131d7a2))
- **unifi**: Add Traefik configuration for guest portal access ([`2a02cc5`](https://github.com/DevSecNinja/truenas-apps/commit/2a02cc5799fe92039ea35cea4efc8603561100e9))
- **adguard**: Add remote control configuration for unbound ([`deaaab5`](https://github.com/DevSecNinja/truenas-apps/commit/deaaab541f581fb74ec215f52a077d216b01263e))
- **plex**: Add README for Plex service setup and configuration details ([`3caab12`](https://github.com/DevSecNinja/truenas-apps/commit/3caab128b4db628cf2bf9fbb41185c428b935e9e))
- **dccd**: Add new deployment aliases for all apps and graceful updates ([`0490dc2`](https://github.com/DevSecNinja/truenas-apps/commit/0490dc266099f48194749c2042442268ede77a7a))
- **architecture**: Update dataset structure and permissions for media and downloads ([`bb784d0`](https://github.com/DevSecNinja/truenas-apps/commit/bb784d0209a3f4e01ed469a4ac800e6b09f289fb))
- **aliases**: Add shell aliases and helper functions for Docker management ([`fe7c34d`](https://github.com/DevSecNinja/truenas-apps/commit/fe7c34d9efbd6da757e1f7ab94f2e79e22d696cd))
- **gatus**: Add DNS health checks for AdGuard and external resolution validation ([`295787b`](https://github.com/DevSecNinja/truenas-apps/commit/295787b74683e91c917cc170d8d7f63a5a24e2b5))

### Miscellaneous

- **deps**: Update docker.io/library/alpine docker tag to v3.23 ([`72adc9f`](https://github.com/DevSecNinja/truenas-apps/commit/72adc9ffc823c32e687b27e4702f0eae804fb6fd))

## [0.9.0] - 2026-04-04

### Bug Fixes

- **unbound**: Comment out unused A records for SVLPROD and SVLINFRA ([`8079b28`](https://github.com/DevSecNinja/truenas-apps/commit/8079b28405b4b4ac1068ca0ebb13b8d6647eea50))
- **unbound**: Update unifi A records to point to SVLNAS instead of SVLINFRA ([`2d93190`](https://github.com/DevSecNinja/truenas-apps/commit/2d931904f92c2b1f2fcce249b7af68d0b21a3226))
- **unifi**: Increase pids_limit to 300 to prevent thread creation errors under load ([`7513c1a`](https://github.com/DevSecNinja/truenas-apps/commit/7513c1a84a180182dabb845b00a21d3ef0c47b1a))
- **mongo-init**: Add dbOwner role for temporary restore database to ensure successful restores ([`58187c7`](https://github.com/DevSecNinja/truenas-apps/commit/58187c7475ba6e2faeb09709765ea8e0734aed5d))
- **image-security**: Update SARIF upload process to combine per-image results into a single file ([`13625f1`](https://github.com/DevSecNinja/truenas-apps/commit/13625f12b0e7a04e36e2d79ed03a5ee99d3f1125))
- **image-security**: Update script comments and ensure unique runAutomationDetails.id for SARIF uploads ([`6c19b53`](https://github.com/DevSecNinja/truenas-apps/commit/6c19b53d3d62678c33a59ec939365db3c83f2b69))
- **renovate**: Update minimum release age for various managers and datasources to 14 days ([`4644903`](https://github.com/DevSecNinja/truenas-apps/commit/464490362739799b251ce7887fc7787efbe81216))
- **image-security**: Ensure image age check job runs only on non-pull request events ([`a26c2f0`](https://github.com/DevSecNinja/truenas-apps/commit/a26c2f07d62e9d76b3e539c0af5ec4ab80742342))
- **envsubst**: Handle unresolved placeholders gracefully in envsubst scripts ([`1d8ddf3`](https://github.com/DevSecNinja/truenas-apps/commit/1d8ddf3557a60603cd8b1131b3fb1e517a2007b3))
- **envsubst**: Update comments to clarify placeholder format in scripts ([`d9655fc`](https://github.com/DevSecNinja/truenas-apps/commit/d9655fcc0ddb102ab7303ff7ed0ec92501b5179c))
- **envsubst**: Improve unresolved placeholder detection by including line numbers ([`f3ea267`](https://github.com/DevSecNinja/truenas-apps/commit/f3ea267fdb8afe233cbd9b11f60be40d9bccd02e))
- **homepage**: Adjust tmpfs configuration to prevent EROFS warning and ensure app stability ([`188acea`](https://github.com/DevSecNinja/truenas-apps/commit/188aceada2abaf0b725a0142d61d7cbdbecec9b7))
- **adguard**: Remove HaGeZi's DynDNS Blocklist from filters section in AdGuardHome configuration ([`7fa4313`](https://github.com/DevSecNinja/truenas-apps/commit/7fa4313540d4dab6cb6f512899be29f93cb95320))
- **adguard**: Remove HaGeZi's DNS Rebind Protection filter and adjust IDs for consistency ([`2a5e801`](https://github.com/DevSecNinja/truenas-apps/commit/2a5e80125693fcea22d9236eceb64d4c843c381c))
- **adguard,dccd**: Enhance ownership commands in scripts and compose files with verbose output for better debugging ([`cfd8e8d`](https://github.com/DevSecNinja/truenas-apps/commit/cfd8e8d41eb2eddc3faee75ee61157db321f8a80))
- **adguard**: Update AdGuard configuration and scripts for improved functionality and security ([`412b529`](https://github.com/DevSecNinja/truenas-apps/commit/412b529edfc061082126f176e4db5f4a6dcaada3))
- **dozzle,immich**: Update socket-proxy and postgres images to latest versions in compose files ([`c690eb2`](https://github.com/DevSecNinja/truenas-apps/commit/c690eb2f18bea26df726225baedd98de5cd80b8e))
- **image-security**: Enhance image age check script to determine last pushed timestamp from Docker Hub and improve handling of OCI config timestamps ([`236764b`](https://github.com/DevSecNinja/truenas-apps/commit/236764b273d13a8b8c4e3996a36414a34b156b53))
- **image-security**: Remove unnecessary exit statement from stale image detection script ([`21fcfc4`](https://github.com/DevSecNinja/truenas-apps/commit/21fcfc4ab0465a8c666d7eed46d7e5058646a6b1))
- **image-security**: Enhance Trivy image scan script to validate SARIF output and improve error handling ([`834a693`](https://github.com/DevSecNinja/truenas-apps/commit/834a6935384c98b0be9b4d2f914ca9206516f49d))
- **image-security**: Enhance stale image detection script to improve issue creation and message clarity ([`ce74dd7`](https://github.com/DevSecNinja/truenas-apps/commit/ce74dd7758774285dc7657a5455902c4966d27b2))
- **image-security**: Improve error handling in image age check and enhance SARIF merging in vulnerability scan ([`b833130`](https://github.com/DevSecNinja/truenas-apps/commit/b833130083c97ec1a11b53d2e4eb8b1a09d55156))
- **adguard**: Uncomment logging configuration in forward-records.conf for visibility in docker logs ([`5a1ad92`](https://github.com/DevSecNinja/truenas-apps/commit/5a1ad92b74f02789d8f9054d3a5cd8642771f0a4))
- **adguard**: Network configuration: change adguard-unbound to use adguard-frontend and remove adguard-backend ([`ebab7e1`](https://github.com/DevSecNinja/truenas-apps/commit/ebab7e1900ca8f0e2f4d59c41ebcdf98d73e57fc))
- **adguard**: Refactor logging configuration: comment out logging settings in forward-records.conf ([`7310c75`](https://github.com/DevSecNinja/truenas-apps/commit/7310c75d0ca43780fa283653be0dcb10bafa299b))
- **adguard**: Enhance healthcheck command: ensure successful DNS resolution by checking for NOERROR response ([`41d6582`](https://github.com/DevSecNinja/truenas-apps/commit/41d658263f28c1b0ff6869bc18fe3f9581bc519a))
- **adguard,dccd**: Enhance log_message function in dccd.sh with colorized output for better visibility; remove unnecessary newline in AdGuardHome.yaml ([`3e9bcea`](https://github.com/DevSecNinja/truenas-apps/commit/3e9bcea8a94d4c19b9d9c2db019709a2beff8365))
- **adguard**: Update AdGuardHome configuration: disable IPv6 for now & update to latest schema v33 ([`d5b0dca`](https://github.com/DevSecNinja/truenas-apps/commit/d5b0dca47c784762b6776ccc309cb6c96201528d))
- **gatus,traefik-forward-auth**: Remove commented-out HTTP endpoint configurations and update DNS query name in Gatus config; add Gatus health check URL in Traefik Forward Auth compose file ([`7fdaa39`](https://github.com/DevSecNinja/truenas-apps/commit/7fdaa39373f4f10ce0bd75a92d9d47c168493e9b))
- **metube**: Update download path for metube service to use archive pool ([`debc193`](https://github.com/DevSecNinja/truenas-apps/commit/debc193eb2a58eaa977a74c6ddb40d315c6b51d0))
- **plex**: Update PLEX_CLAIM_TOKEN ([`5d84ef9`](https://github.com/DevSecNinja/truenas-apps/commit/5d84ef9791c39932dca2ce4e5839a79b3aa873c0))
- **architecture,immich**: Update architecture and compose documentation for private data groups ([`97d0d95`](https://github.com/DevSecNinja/truenas-apps/commit/97d0d95e0278c2d9ea41fedc627280b921451783))
- **plex**: Remove exposed port mapping for plex service after initial setup ([`198f207`](https://github.com/DevSecNinja/truenas-apps/commit/198f207b8dfae5858e483bd5d0fe0977cdb9610c))
- **plex**: Update PLEX_CLAIM_TOKEN and metadata in secret.sops.env for consistency ([`7ac899c`](https://github.com/DevSecNinja/truenas-apps/commit/7ac899cfedf13d7e1b716fc61780bbf394114e81))
- **plex**: Ownership command for plex-init service to match media-readers GID ([`2988315`](https://github.com/DevSecNinja/truenas-apps/commit/2988315858f9a7aaddd6f771d8b04340b11a8db2))
- **traefik**: Ownership and permissions setup for acme directory in traefik-init service ([`773c9c6`](https://github.com/DevSecNinja/truenas-apps/commit/773c9c6f91061c41e1a4de2ac0787773a391fa2e))
- **adguard**: Enhance adguard-init service to seed AdGuardHome.yaml on fresh installs and ensure proper ownership of directories ([`7a09a60`](https://github.com/DevSecNinja/truenas-apps/commit/7a09a60367d1090bc567b263b63f3e4baf6fa36f))
- **compose**: Update image references to include docker.io prefix and add healthchecks ([`5b9284f`](https://github.com/DevSecNinja/truenas-apps/commit/5b9284fe3804a1fb0ef41bb1c45ec65765e99b0b))
- **dccd,immich**: Enhance dccd.sh to ignore file permission changes and update compose.yaml to set read-only and tmpfs options for improved security ([`76a3042`](https://github.com/DevSecNinja/truenas-apps/commit/76a3042bf71e0ad0ec91cfdf8227dc7ff1ae8556))
- **immich**: Comment out hardware acceleration configuration in compose file for future re-enablement ([`b04fe53`](https://github.com/DevSecNinja/truenas-apps/commit/b04fe53113e9654d5e617800133855baa3ef0a60))

### CI/CD

- **github**: Add bug and enhancement labels to GitHub labels configuration ([`f451533`](https://github.com/DevSecNinja/truenas-apps/commit/f451533370a59dec87617ca84a05a9ed3eac7cc3))
- Add GitHub workflows for label synchronization and image security checks ([`7d52190`](https://github.com/DevSecNinja/truenas-apps/commit/7d521907c9dfc619f874c0b0f66701775de939b4))
- **image-security**: Add GitHub Actions for stale image detection and vulnerability scanning ([`05de2f3`](https://github.com/DevSecNinja/truenas-apps/commit/05de2f3ad57c5b342b0d767264f43906f987ba06))

### Documentation

- **config.yaml**: Clarify envsubst placeholder format in comments ([`5e125a1`](https://github.com/DevSecNinja/truenas-apps/commit/5e125a1b998989602decbf7ba4874259ffbb1ad2))
- **github**: Add Copilot instructions for repository setup and validation ([`f22079a`](https://github.com/DevSecNinja/truenas-apps/commit/f22079ad3539e3e64b0e3ae9bd12da4317e4c4b0))
- **architecture**: Update architecture documentation to improve clarity on init container usage and volume ownership ([`261de11`](https://github.com/DevSecNinja/truenas-apps/commit/261de113898600d4be407faed288fbd587894664))
- **architecture**: Clarify requirements for init containers regarding DAC_OVERRIDE and bind-mount paths in architecture documentation ([`aea7315`](https://github.com/DevSecNinja/truenas-apps/commit/aea73150e0650a3bac42ff5695378023c21dd311))
- **architecture**: Update documentation for dataset permissions and cloning process ([`d9fd27b`](https://github.com/DevSecNinja/truenas-apps/commit/d9fd27b397fae8e4b248840b3b113a0160cda9a7))
- **disaster-recovery**: Update disaster recovery instructions for repository cloning process ([`9733a5f`](https://github.com/DevSecNinja/truenas-apps/commit/9733a5f2d5313bdfe2128b048e119f0de135d327))
- **architecture,disaster-recovery**: Add disaster recovery documentation for TrueNAS app stack restoration ([`9bcc3fd`](https://github.com/DevSecNinja/truenas-apps/commit/9bcc3fd856f30c93e41fec06081164a91ee46c66))
- **architecture**: Fix formatting of NFSv4 ACL entries in architecture documentation ([`11673fa`](https://github.com/DevSecNinja/truenas-apps/commit/11673fa7d218ebe123688139b148d3d7939f574a))
- **architecture**: Update architecture documentation for Apps dataset ACLs and permissions ([`2395f6d`](https://github.com/DevSecNinja/truenas-apps/commit/2395f6dcaf5812eab485b1321c40eeeea43e77d4))

### Features

- **homepage,traefik-forward-auth**: Add tmpfs mount for Next.js server pages and enhance placeholder verification in envsubst script ([`d8aa416`](https://github.com/DevSecNinja/truenas-apps/commit/d8aa416fa3c0e17c1c87c81011eaae24ad846cff))
- **dozzle**: Add init container for data ownership setup ([`1c2b30b`](https://github.com/DevSecNinja/truenas-apps/commit/1c2b30bd8066f5012aca18d720b49cd4c86b81ff))
- **adguard**: Add CA certificates bundle to unbound configuration for upstream DoT verification ([`8749895`](https://github.com/DevSecNinja/truenas-apps/commit/87498953a39699960776b1da57ac78203f309112))
- **renovate**: Add custom versioning for linuxserver images in Renovate configuration ([`021913d`](https://github.com/DevSecNinja/truenas-apps/commit/021913d4177757f018808b5da82bb6d6274e6064))
- **adguard**: Add logfile, verbosity, and log-servfail settings to forward-records.conf ([`680f334`](https://github.com/DevSecNinja/truenas-apps/commit/680f334c5ad6fd981c6a22d72be45b10a69cfc89))
- **adguard**: Add external domain resolution to unbound healthcheck ([`dc650cd`](https://github.com/DevSecNinja/truenas-apps/commit/dc650cdbe7a559bb32e3bd1fd5f9e0114f8da713))
- **adguard**: Add security and ad-blocking filter lists to AdGuardHome configuration ([`a52e1bb`](https://github.com/DevSecNinja/truenas-apps/commit/a52e1bb51714c9c8bfedd988ea5dcab5f1ccd021))
- **adguard,dozzle**: Add subdomain entry for logs service and enable system info in Dozzle ([`85e105b`](https://github.com/DevSecNinja/truenas-apps/commit/85e105b1a132a875fb33ab1bbe0c304a76d5fffa))
- **dozzle,traefik**: Add Dozzle service and update architecture documentation ([`726f1b8`](https://github.com/DevSecNinja/truenas-apps/commit/726f1b866fd9ed5e8f5b82a6d4a6332ddc606a8d))
- **immich**: Add /run tmpfs mount for gunicorn socket in immich server ([`5819058`](https://github.com/DevSecNinja/truenas-apps/commit/5819058f0c4d60c9648e353199117ba28c2e2adc))
- **immich**: Add DAC_OVERRIDE capability for immich-server to enable recursive chown on /upload ([`e62c3e6`](https://github.com/DevSecNinja/truenas-apps/commit/e62c3e6bf8b689cc4b058531188236affb6fb06f))
- **gatus**: Add TODO note for healthcheck support in gatus service ([`fab8ea9`](https://github.com/DevSecNinja/truenas-apps/commit/fab8ea924573804042c11c31721bfd6f411fa200))
- **renovate**: Add minimum release age for various managers and datasources in renovate configuration ([`c4db6e5`](https://github.com/DevSecNinja/truenas-apps/commit/c4db6e539b4323ef02944281fd94485a72afa5b1))
- **plex**: Add KILL capability for temporary Plex process during server claiming ([`d2342f3`](https://github.com/DevSecNinja/truenas-apps/commit/d2342f3b26485a27243f0654b20e76ddf1c3cea2))
- **plex**: Add plex-init service to set ownership of plex-data volume on fresh installs ([`24a19aa`](https://github.com/DevSecNinja/truenas-apps/commit/24a19aae90ba52f94f68d63a2c553cd257f3af81))
- **gatus**: Add gatus-init service to manage config ownership and permissions ([`c2c9772`](https://github.com/DevSecNinja/truenas-apps/commit/c2c9772013867d9e624b2ad808cb60c229595584))

### Miscellaneous

- **deps**: Update ghcr.io/immich-app/postgres docker tag to v18 ([`baf7a25`](https://github.com/DevSecNinja/truenas-apps/commit/baf7a252caa754a6ed693e71b1a5b14d81e15347))
- **deps**: Update lscr.io/linuxserver/unifi-network-application docker tag to version-10.1.89 ([`59a632e`](https://github.com/DevSecNinja/truenas-apps/commit/59a632e23e10f3930258c0eae13db440715fbe67))
- **adguard**: Improve healthcheck for adguard-unbound service and add verification for unresolved placeholders in envsubst script ([`8fbee78`](https://github.com/DevSecNinja/truenas-apps/commit/8fbee7878cb4e9ba5e9ae05419575f0c1f463e43))
- **adguard**: Add validation comment for adguard-unbound configuration in compose.yaml ([`f29939d`](https://github.com/DevSecNinja/truenas-apps/commit/f29939d9d67a88399bab67827769a8fdde900d33))
- **deps**: Update dependency jdx/mise to v2026.4.3 ([`b0ba2f3`](https://github.com/DevSecNinja/truenas-apps/commit/b0ba2f3ce591a996f79fb756de0a4ca9fdeec7af))
- **adguard**: Let Unbound do the caching ([`a189e98`](https://github.com/DevSecNinja/truenas-apps/commit/a189e98e2d700c4364277543797e6325fe59b906))
- **plex**: Refine ownership setup for plex-init service to ensure proper permissions on fresh installs ([`1ad03df`](https://github.com/DevSecNinja/truenas-apps/commit/1ad03dff695a68695d37d36baa70f0c535cfa7aa))
- **immich**: Temporarily disable read-only and tmpfs options for immich-server due to compatibility issues ([`24ab05a`](https://github.com/DevSecNinja/truenas-apps/commit/24ab05acbb552816936e84b928f644977fa1b4c4))
- **deps**: Update docker.io/valkey/valkey:9-alpine Docker digest to e1095c6 ([`9cf634f`](https://github.com/DevSecNinja/truenas-apps/commit/9cf634fc4ae179a4fc88cad232851d059aff8370))

### Refactoring

- Rename src/ to services/ ([`ae4cd0c`](https://github.com/DevSecNinja/truenas-apps/commit/ae4cd0cf61f39bf9c824bed9f3b06d2025c16381))
- **adguard**: Healthcheck for adguard-unbound service to use inline command for better compatibility and reduce dependency on external scripts ([`824dd00`](https://github.com/DevSecNinja/truenas-apps/commit/824dd0009ee0bba33d8a673b4c3ec71e29ae0ee9))
- **adguard**: AdGuard service configuration to enhance security and privilege management ([`0b46d8b`](https://github.com/DevSecNinja/truenas-apps/commit/0b46d8b6c066e2dd6aa60942427d6dcde6b896a4))
- **ci,image-security**: SARIF upload process to handle per-image files and improve empty SARIF generation ([`1b77fe6`](https://github.com/DevSecNinja/truenas-apps/commit/1b77fe6ce32487c076e8128de1b09b13511ebe89))
- **image-security**: SARIF merging logic to improve handling of multiple runs and deduplicate rules ([`14159bd`](https://github.com/DevSecNinja/truenas-apps/commit/14159bdffac8c85f1c35edb72acc1c45e4c9731a))
- **adguard**: Update adguard-unbound-init ownership and command execution ([`a55de41`](https://github.com/DevSecNinja/truenas-apps/commit/a55de4156f5cc065a74abb30b46230921be216d5))
- **adguard**: Remove redundant WPAD local-zone entry from forward-records.conf ([`f1ed4f8`](https://github.com/DevSecNinja/truenas-apps/commit/f1ed4f88782d1df5f50ae8377a73f3b41d0ccbd1))
- **adguard**: AdGuard configuration: update rate limits, adjust upstream timeout, enable log compression, and modify DNS forwarding settings ([`c38f1aa`](https://github.com/DevSecNinja/truenas-apps/commit/c38f1aa059afa72fb73c9a6e8ecf7c744ab60dc7))
- **adguard,gatus**: Volume mounts in compose files to use bind mounts for data directories ([`8a13870`](https://github.com/DevSecNinja/truenas-apps/commit/8a138706810f40be93f7ca3443b5f97ed9818380))
- **dccd**: Migrating to encrypted apps folder and therefore updating dataset references from 'Apps' to 'apps' ([`8b6b28f`](https://github.com/DevSecNinja/truenas-apps/commit/8b6b28f1405d37b11c688abcee90fe0fa9f750c7))
- Implement new PUID/GUID across services ([`8cbe2c4`](https://github.com/DevSecNinja/truenas-apps/commit/8cbe2c4fda6d49d5770dae86e0b4b6471d31c0e7))

## [0.8.0] - 2026-04-02

### Bug Fixes

- **traefik**: Update Immich middleware chains to use loose rate limiting for improved performance ([`f0857f5`](https://github.com/DevSecNinja/truenas-apps/commit/f0857f556b619b321d179d4a1a0a401abb72932a))
- **homepage**: Reorder commands in homepage-init to ensure permissions are set before ownership ([`2fc3257`](https://github.com/DevSecNinja/truenas-apps/commit/2fc32574b1bc7fbe94b4b8ec564afb6e8c2692dc))
- **homepage**: Update homepage-init command to set directory and file permissions for /config ([`b1ae568`](https://github.com/DevSecNinja/truenas-apps/commit/b1ae568ffbe6b557edfb4f67e33a7cbaf2d2d8eb))
- **immich**: Update healthcheck command for Redis service to use valkey-cli ([`32cf9df`](https://github.com/DevSecNinja/truenas-apps/commit/32cf9df3ed924a1fdf3b3fe0096646111c5e8ca1))
- **dccd**: Update Gatus CD key format to match external-endpoint definition in config ([`ef44083`](https://github.com/DevSecNinja/truenas-apps/commit/ef44083f41d2cd1e4af38becc5ba989b9eae03ca))
- **dccd**: Enhance Gatus CD token sourcing from .env file and update usage instructions ([`6c7f75e`](https://github.com/DevSecNinja/truenas-apps/commit/6c7f75e058e3f04ec4684e3ad0ba3806373e599d))
- **homepage**: Update PGID for homepage ([`69fed9a`](https://github.com/DevSecNinja/truenas-apps/commit/69fed9abcccc1d73a04c6088681d45da9f4d8c0a))
- **vscode**: Update age key file path in VSCode settings ([`5956793`](https://github.com/DevSecNinja/truenas-apps/commit/595679376b508946a6de2cae7386e1dc2ec7b405))
- **gatus**: Disable automatic monitoring in Gatus ([`098c9cb`](https://github.com/DevSecNinja/truenas-apps/commit/098c9cbd74ed3c8033272b5dd900c5cfdf7a4026))
- **mise**: Duplicate entry for checkov in mise.toml ([`f138dc4`](https://github.com/DevSecNinja/truenas-apps/commit/f138dc4b70d0b65bc521a1192ae7f9898d25f839))
- **mise**: Update mise.lock to add provenance for actionlint, lefthook, and zizmor tools ([`92f1651`](https://github.com/DevSecNinja/truenas-apps/commit/92f165198bc86feef3f726156223f2aa847c2f49))
- **devcontainer**: Update devcontainer configuration to include dprint path and maintain consistency ([`158b2f6`](https://github.com/DevSecNinja/truenas-apps/commit/158b2f6e2dbdfd416e4cf765fcc4bec0ea5f1501))

### Documentation

- **github**: Add prompt for creating new Docker Compose apps in TrueNAS repository ([`d97e0bc`](https://github.com/DevSecNinja/truenas-apps/commit/d97e0bca0c64b90aa8329b62d49659cb6e0ed6d3))

### Features

- **traefik**: Add Immich-specific middleware chains and secure headers for enhanced security ([`4b6b6bd`](https://github.com/DevSecNinja/truenas-apps/commit/4b6b6bdb2686fa58b14e9eb747829459cc68d6c9))
- **homepage**: Add FOWNER capability to homepage service for file permission management ([`278615f`](https://github.com/DevSecNinja/truenas-apps/commit/278615fe230f5cb1a9eacce17ee3592ae09a9da1))
- **dccd**: Add error tracking for deployment failures in dccd.sh ([`b076e30`](https://github.com/DevSecNinja/truenas-apps/commit/b076e30d072517d3a1607cc7df23d9869cf6037e))
- **immich**: Add SETUID and SETGID capabilities for Valkey's entrypoint in Redis service ([`7de9308`](https://github.com/DevSecNinja/truenas-apps/commit/7de9308479067fb59e93dcab755140909a2cbc9a))
- **immich**: Add capability to chown /data for Valkey's entrypoint in Redis service ([`6ee407b`](https://github.com/DevSecNinja/truenas-apps/commit/6ee407b8a46cf80d80caa55f154084042d753aac))
- **dccd**: Add support for sourcing Gatus CD token from .env file if not set ([`2f804d9`](https://github.com/DevSecNinja/truenas-apps/commit/2f804d92a8a2aa13f842fcbd8709256c1db5d4f1))
- **immich,shared**: Add Immich service configuration and environment setup for TrueNAS ([`d6c7669`](https://github.com/DevSecNinja/truenas-apps/commit/d6c766921b482c47197b1a91d1a9f538f272409f))
- **adguard**: Add A records for adguard, apps, status, and traefik services ([`9194e97`](https://github.com/DevSecNinja/truenas-apps/commit/9194e970a09d1bc7e077592c7692f6de5490e79f))
- **renovate**: Add rule to flag stale dependencies over 1 year old ([`f82c8d1`](https://github.com/DevSecNinja/truenas-apps/commit/f82c8d14ea0ddc1ddc333d94574856198747c258))
- **dccd,gatus**: Add Gatus external endpoint webhook for cd status ([`bf3ca3a`](https://github.com/DevSecNinja/truenas-apps/commit/bf3ca3ac7ceff4260051900767306172e10e60c4))
- **gatus**: Add Gatus endpoints to default Docker group ([`df5b808`](https://github.com/DevSecNinja/truenas-apps/commit/df5b808e58a258c2ad6ccc4c347edaeb2c0deae1))
- **dccd**: Add --build option to redeploy and update compose commands ([`beedd7d`](https://github.com/DevSecNinja/truenas-apps/commit/beedd7d7ae2eb368dc1f41be7c8899a28b4058a0))
- **gatus**: Add GATUS_CONFIG_PATH environment variable to gatus service ([`cfa31bf`](https://github.com/DevSecNinja/truenas-apps/commit/cfa31bf0b2bf3937ecd080e348b3c89be3022b22))
- **gatus**: Add gatus-sidecar and gatus-docker-proxy services to compose.yaml ([`996d243`](https://github.com/DevSecNinja/truenas-apps/commit/996d243493f2cf0ee80f3f34aa5615d529cd9683))
- **devcontainer**: Add devcontainer configuration for development environment ([`2fcbe9e`](https://github.com/DevSecNinja/truenas-apps/commit/2fcbe9ea459aebe281a806607290c9f3a448b46b))
- **vscode**: Add MCP configuration for GitHub server in VSCode ([`2f35e0e`](https://github.com/DevSecNinja/truenas-apps/commit/2f35e0ea199136a54dd9ad0d38104d0ec1ba2ae0))

### Miscellaneous

- **devcontainer**: Add git.postCommitCommand setting to disable post-commit hooks ([`5c32d2f`](https://github.com/DevSecNinja/truenas-apps/commit/5c32d2fcd25b55ee2235c0b0efa8e3835feb49e8))
- **deps**: Update ghcr.io/immich-app/postgres Docker tag to v16 ([`999754b`](https://github.com/DevSecNinja/truenas-apps/commit/999754b39f6c0f4e6dacce755cb984e7735c2e6d))
- **deps**: Update immich monorepo to v2.6.3 ([`4a08415`](https://github.com/DevSecNinja/truenas-apps/commit/4a084152a98198b19b73fb50694b7c7e1376a402))
- **vscode**: Change default terminal profile to fish in VSCode settings ([`dbb51f5`](https://github.com/DevSecNinja/truenas-apps/commit/dbb51f51fde38c0c02f0dc292834b985dd12e3a1))
- **mise**: Add provenance information for actionlint and lefthook platforms ([`47b99dc`](https://github.com/DevSecNinja/truenas-apps/commit/47b99dc10e58f2e29f7aab607464befa0ad949a3))
- **deps**: Update ghcr.io/alexta69/metube:latest Docker digest to db96c7d ([`2ffc76d`](https://github.com/DevSecNinja/truenas-apps/commit/2ffc76d1b2e87787ff428dbb6864294d4b2291a8))
- **deps**: Update dependency dprint to v0.53.2 ([`fae2e02`](https://github.com/DevSecNinja/truenas-apps/commit/fae2e029c71ca4f1e2aa83731eb63005de410660))
- **deps**: Update ghcr.io/gethomepage/homepage Docker tag to v1.12.3 ([`ddb5bc5`](https://github.com/DevSecNinja/truenas-apps/commit/ddb5bc57fbf0150405e8c4a10bdbd5d6e5c89484))
- **deps**: Update dependency jdx/mise to v2026.4.1 ([`77e0aed`](https://github.com/DevSecNinja/truenas-apps/commit/77e0aed908a9493cc68688429271e3275ce055b6))
- **ci**: Only use dotenv-linter when on x86 ([`9399207`](https://github.com/DevSecNinja/truenas-apps/commit/9399207ecfa17a83ebe05d827033c4ac6c9f25bc))
- **deps**: Pin mcr.microsoft.com/devcontainers/base Docker tag to 23fa69f ([`844d222`](https://github.com/DevSecNinja/truenas-apps/commit/844d22262ace255a84b0d1e1c8b8ceb26f27cc0d))
- **deps**: Update docker.io/library/mongo:8.2.6 Docker digest to eea8506 ([`b3e5bbc`](https://github.com/DevSecNinja/truenas-apps/commit/b3e5bbc4112050f6de6925034a80d51cd670f0fc))
- **deps**: Update ghcr.io/gethomepage/homepage Docker tag to v1.12.2 ([`0b44f23`](https://github.com/DevSecNinja/truenas-apps/commit/0b44f2339fca4d4a930b91d817fa532bac53cf8f))
- **deps**: Update dependency pipx to v1.11.1 ([`632612e`](https://github.com/DevSecNinja/truenas-apps/commit/632612eea7fc0bc15e9b24016003a8680f25d98d))
- **deps**: Update dependency jdx/mise to v2026.3.18 ([`b976a61`](https://github.com/DevSecNinja/truenas-apps/commit/b976a61b06467f0c22caedb718674ead9dc476f9))

### Refactoring

- **devcontainer,immich**: VSCode settings and environment files for Immich service ([`deb6645`](https://github.com/DevSecNinja/truenas-apps/commit/deb6645c66f05e4c4078cdf90709ff3179ef9932))

## [0.7.0] - 2026-03-31

### Bug Fixes

- **compose**: Add docker.io prefix to image references in compose files ([`2143caf`](https://github.com/DevSecNinja/truenas-apps/commit/2143caf0bc3bfa3c79707cdf123efe841e476cc5))
- **adguard,homepage**: Enhance ownership commands in compose files to use verbose flags for better logging ([`7bd1100`](https://github.com/DevSecNinja/truenas-apps/commit/7bd11005a8ddc1423cab3b7e98c49a9ed146e8d8))
- **homepage,traefik**: Set docker-config-readers PGID ([`7687ced`](https://github.com/DevSecNinja/truenas-apps/commit/7687ced47d188c61a750b92d51c6e1f9bb8cd3c6))
- **metube**: Leverage built-in healthcheck ([`aefdd98`](https://github.com/DevSecNinja/truenas-apps/commit/aefdd98d84b657d59330f66e70b1c91c9a89fff5))
- **architecture,traefik-forward-auth**: Enhance traefik-forward-auth init container to include chown command for data directory and adjust capabilities for proper ownership management ([`10829fe`](https://github.com/DevSecNinja/truenas-apps/commit/10829fe25ba089f355111cee9768fd8c4ffcabbd))
- **traefik**: Update traefik initialization to set ownership on config directory ([`13d44ef`](https://github.com/DevSecNinja/truenas-apps/commit/13d44efb854b629de12cf399965fb49c95c319b6))
- **dccd**: Update sops file decryption to exclude 'config' directory in search ([`462ae98`](https://github.com/DevSecNinja/truenas-apps/commit/462ae984a61ed669a7bc1cb639d6b6b0e3e11f36))
- **metube**: Enhance MeTube initialization by setting ownership on metube-state volume and pre-creating download subdirectories for first boot. Update environment variable handling for GID and adjust commands for proper directory setup ([`c11b68f`](https://github.com/DevSecNinja/truenas-apps/commit/c11b68f19e367af0f4b962a6fcc5ecc244136292))
- **plex**: Update Plex service configuration comments for clarity on UID ownership and environment variable settings ([`00da50d`](https://github.com/DevSecNinja/truenas-apps/commit/00da50d6b9b45b7a37f379bf3e902256fb67b859))
- **plex**: Update Plex service configuration to enable read-only operation and adjust tmpfs settings for improved security and functionality ([`100a04a`](https://github.com/DevSecNinja/truenas-apps/commit/100a04ab1e2aae280874b7425aae2f97a4339952))
- **plex**: Update Plex setup instructions and expose port 32400 for initial configuration ([`a981fb3`](https://github.com/DevSecNinja/truenas-apps/commit/a981fb3d4be62634a0f51a9f8cde5326b6a6015a))
- **vscode**: Remove dprint extension from VSCode recommendations ([`67cc6ce`](https://github.com/DevSecNinja/truenas-apps/commit/67cc6ce796518d4893a11b4dd5e30f587b97ec8e))
- **plex**: Update PLEX_CLAIM_TOKEN and metadata in secret.sops.env ([`5b6959c`](https://github.com/DevSecNinja/truenas-apps/commit/5b6959ce85b779a44d9ceca480328a7f96138d62))
- **plex**: Increase pids_limit for Plex service to accommodate more threads for plugins, DB, and transcoding ([`ed40956`](https://github.com/DevSecNinja/truenas-apps/commit/ed409563ff0b2f79e6c46038f48fc959b5388737))
- **renovate**: Workaround for Renovate bug (renovatebot/renovate#24942) where custom regex manager cannot perform initial digest pin ([`495bc0c`](https://github.com/DevSecNinja/truenas-apps/commit/495bc0c069117e00922a4916fe7a996e5b3606bc))
- **gatus,unifi**: Update backup image references from tiredofit to nfrastack in compose files ([`0bf6734`](https://github.com/DevSecNinja/truenas-apps/commit/0bf6734f7b9710a162c9678850f62de730cb0482))
- **gatus,unifi**: Enable one-shot backup on docker compose up ([`c66eaab`](https://github.com/DevSecNinja/truenas-apps/commit/c66eaabc9cfa2c638cf2f6f695a967732d9679cc))
- **gatus**: PostgreSQL volume path and remove unnecessary PGDATA environment variable ([`d7b6b43`](https://github.com/DevSecNinja/truenas-apps/commit/d7b6b43e93d5025999bbafdd0a04dea8414b5c82))
- **dccd,gatus**: Increase WAIT_TIMEOUT to 120 seconds and extend start_period to 30 seconds for service health checks ([`d983da9`](https://github.com/DevSecNinja/truenas-apps/commit/d983da9e19d1c91eaf4363874172f176eea8184d))
- **dprint**: Formatting in markdownlint configuration file ([`47b8b3b`](https://github.com/DevSecNinja/truenas-apps/commit/47b8b3b9492255192f5d7c576c5ebc8bbfa9a76f))

### Documentation

- **architecture**: Add explicit registry prefix requirement for images in architecture documentation ([`0a809ac`](https://github.com/DevSecNinja/truenas-apps/commit/0a809ac3f99426975fdea314e69e2d823bdbc1c2))
- **architecture**: Fix table ([`4eff5be`](https://github.com/DevSecNinja/truenas-apps/commit/4eff5be60834475c0588f70a5ba1d108bb6e1dbd))
- **architecture,plex**: Clarify s6-overlay exceptions for writable root filesystem and capabilities ([`e6881b3`](https://github.com/DevSecNinja/truenas-apps/commit/e6881b3cf94a948316c4ea82da7ecb698f5d4f3a))
- **architecture**: Document pitfalls of using s6-overlay images regarding read-only and group settings ([`6c9506a`](https://github.com/DevSecNinja/truenas-apps/commit/6c9506a103a2c21cbf2266d26e6b987d76f149b4))
- **architecture**: Refactor environment variable documentation for improved clarity and consistency ([`cee508b`](https://github.com/DevSecNinja/truenas-apps/commit/cee508b06b3c3f68aae17f12f0e3551e13edf5e2))
- **database**: Add documentation for PostgreSQL major version upgrades and migration steps ([`f897225`](https://github.com/DevSecNinja/truenas-apps/commit/f89722504b452f565c08c27cbf16166cf34b1c31))

### Features

- **metube,traefik**: Add MeTube service configuration and update architecture documentation ([`dacde78`](https://github.com/DevSecNinja/truenas-apps/commit/dacde785bf068b44657d7caeae36a93e61c601ec))
- Add actionlint platform configurations for various architectures ([`e4a6bfb`](https://github.com/DevSecNinja/truenas-apps/commit/e4a6bfbca4dd2202e91f257f9a381f995ea7a771))
- **plex**: Add Traefik load balancer configuration for Plex service ([`577beda`](https://github.com/DevSecNinja/truenas-apps/commit/577bedab77e646a7dc727a740f313cfbc598da3b))
- **dccd**: Add APP_FILTER and NO_PULL options to dccd.sh for selective deployment and image pull control ([`65b5e97`](https://github.com/DevSecNinja/truenas-apps/commit/65b5e97383c6e520d3f2254b8076037723c47572))
- **plex,traefik**: Add Plex-specific middleware chain with relaxed CSP for web app access ([`35a507b`](https://github.com/DevSecNinja/truenas-apps/commit/35a507bab460ce491ff54a07363174ea46f4c040))
- **plex,traefik**: Add Plex service configuration and update architecture documentation ([`2233451`](https://github.com/DevSecNinja/truenas-apps/commit/2233451dc2f48916f5f85281965a2b89bad314c5))
- **renovate**: Add package rule to disable digest pinning for 'mise' manager ([`f3f17c1`](https://github.com/DevSecNinja/truenas-apps/commit/f3f17c12bab5901a3c0d9e84db27954e3c0fafe1))
- **gatus,unifi**: Add backup command to gatus and unifi services in compose files ([`40dc8e7`](https://github.com/DevSecNinja/truenas-apps/commit/40dc8e7cbff603e83fc2b8ef0172177e7a83d6a6))
- **dprint**: Add markdownlint configuration file with default rules ([`b7c0f6b`](https://github.com/DevSecNinja/truenas-apps/commit/b7c0f6b7db2a228ea7bb1a5f583dc4e954007ade))
- **dprint**: Implement dprint linter ([`8577d7e`](https://github.com/DevSecNinja/truenas-apps/commit/8577d7e0bdb68bc357c4abea1f16386c8b060fb8))

### Miscellaneous

- **dccd**: Get all containers - not only running ([`357121e`](https://github.com/DevSecNinja/truenas-apps/commit/357121e1f49fbc892c916e854d29e4975f701273))
- **deps**: Update dependency actionlint to v1.7.12 ([`8c110ca`](https://github.com/DevSecNinja/truenas-apps/commit/8c110ca3f5afe816f370485962853c7aa0a71597))
- **deps**: Update lscr.io/linuxserver/plex:version-1.43.0.10492-121068a07 Docker digest to cbd631f ([`113f571`](https://github.com/DevSecNinja/truenas-apps/commit/113f571678d61eadf17684c9aa16cdbf55cf67a1))
- **mise**: Sort tools ([`94a0dbc`](https://github.com/DevSecNinja/truenas-apps/commit/94a0dbc16ecf3b8ad3d1c701bc588c9b3407e7df))
- **deps**: Update postgres to v18 ([`0f6bede`](https://github.com/DevSecNinja/truenas-apps/commit/0f6bededc14c924e2cc419242b37dfb22d1475fd))
- **deps**: Update ghcr.io/italypaleale/traefik-forward-auth Docker tag to v4.8.0 ([`fa13881`](https://github.com/DevSecNinja/truenas-apps/commit/fa13881a9991998d2e22f54378cad3de624030d7))

### Other

- **plex**: Plex as read_only as it will break groups, so can't access media files based on PGID anymore ([`1b4f204`](https://github.com/DevSecNinja/truenas-apps/commit/1b4f20452b6a1cfa04f2a05da372eb01233ebc5f))
- **traefik**: Revert "Revert CSP for Plex" ([`20ca5b8`](https://github.com/DevSecNinja/truenas-apps/commit/20ca5b86b8c9ce76a8ed46fc4ad447e69cb6e7e0))
- **traefik**: Revert CSP for Plex ([`f5589ce`](https://github.com/DevSecNinja/truenas-apps/commit/f5589ce02c7cd1e10d3756ee5b28a8591a717cd1))
- **gatus,unifi**: Revert backup image references from nfrastack to tiredofit ([`1cfc1a5`](https://github.com/DevSecNinja/truenas-apps/commit/1cfc1a556ee191c563d2c918b284753d39f1901f))

### Refactoring

- **plex,shared**: Media access environment variables and update Plex service configuration for improved clarity and functionality ([`98ca13c`](https://github.com/DevSecNinja/truenas-apps/commit/98ca13ca1c8e68416d2f6201c13eada61dec23df))
- **traefik**: Plex middleware to replace middlewares-plex-headers with middlewares-plex-secure-headers for improved security and functionality ([`c3a4c2e`](https://github.com/DevSecNinja/truenas-apps/commit/c3a4c2e0c4808658d9d9542968531791d6f993f1))
- **plex**: Plex setup instructions to clarify initial configuration steps and remove outdated comments ([`7da3824`](https://github.com/DevSecNinja/truenas-apps/commit/7da3824d692a57969d4b6f78364408c2371a6f2c))
- **dccd**: Git sync logic in dccd.sh to support no-pull mode and improve deployment conditions ([`8ece2da`](https://github.com/DevSecNinja/truenas-apps/commit/8ece2da40bc81ebafd88953a430b08ed9701922f))

## [0.6.0] - 2026-03-29

### Bug Fixes

- **adguard,traefik**: Update Traefik router middlewares to use authentication chain ([`647527c`](https://github.com/DevSecNinja/truenas-apps/commit/647527cfbdc70bede18a8d29fd6b0a7768c2ce91))
- **echo-server,traefik**: Homepage group label for echo-server and traefik services to use 'Infrastructure' ([`19296c9`](https://github.com/DevSecNinja/truenas-apps/commit/19296c9b0e7f887b8ec9013ef4bffc8360a763a3))
- **traefik**: Update forward auth middleware address and add max response body size limit to prevent DoS ([`ea2d768`](https://github.com/DevSecNinja/truenas-apps/commit/ea2d76880f0e86f9e8197a8521ee965d2ee7bb3c))
- **adguard,gatus**: Enhance service capabilities by adding DAC_OVERRIDE and FOWNER to support file ownership changes and directory traversal ([`9491bb6`](https://github.com/DevSecNinja/truenas-apps/commit/9491bb660dca1df35739d49e9f7816284cb75ebb))
- **adguard**: Remove widget configuration from adguard service in compose.yaml ([`71bfe85`](https://github.com/DevSecNinja/truenas-apps/commit/71bfe85fd10a6b1461e23320c32251a80ab7f6b7))
- **renovate**: Update postgres group in renovate.json to include docker.io/library/postgres ([`2872d67`](https://github.com/DevSecNinja/truenas-apps/commit/2872d676beeddac0c465f37b6b128c784502dadc))
- **renovate**: Regex pattern for managerFilePatterns in renovate.json ([`6834ac2`](https://github.com/DevSecNinja/truenas-apps/commit/6834ac2f1473f2dc2dd560793923a8d019eefdab))
- **lefthook**: Update Checkov command to skip download in pre-commit configuration ([`46f1836`](https://github.com/DevSecNinja/truenas-apps/commit/46f18368902b7c892f28df0c6a037e52ba4f3de4))
- **dccd**: Enhance update_compose_files: ensure correct branch checkout before hash comparison ([`df92c6b`](https://github.com/DevSecNinja/truenas-apps/commit/df92c6b7d9bb15300fa10e077f40ef7c863b5bd4))
- **ci**: Bash doesn't expand ** globs by default ([`3fa347e`](https://github.com/DevSecNinja/truenas-apps/commit/3fa347e40be0a6abfa1d16bf567a3d2de9ee6043))
- **adguard,dccd**: ShellCheck findings ([`86ec5fe`](https://github.com/DevSecNinja/truenas-apps/commit/86ec5fea79b05772af6e0720c31016a7b17e5fbd))
- **traefik,yamlfmt**: Update yamlfmt configuration and format Content-Security-Policy in middlewares.yml ([`f681e30`](https://github.com/DevSecNinja/truenas-apps/commit/f681e30afbd050e60263e8690dd7a8d5deb79c7e))

### CI/CD

- **lefthook**: Add dotenv-linter to workflows and pre-commit hooks ([`ab2f6ad`](https://github.com/DevSecNinja/truenas-apps/commit/ab2f6ad913a734e340a0c34127f994c80516f088))
- Implement docker compose config validation in lint workflow ([`c04ace1`](https://github.com/DevSecNinja/truenas-apps/commit/c04ace12711cb52300c93768de0cc4a8b799e59d))
- Add Checkov, Trivy, and Yamllint jobs to CI workflows ([`d906b75`](https://github.com/DevSecNinja/truenas-apps/commit/d906b757d5b35bbc99a1f262372c5c2ec34c88da))
- Update actions/checkout action to v6 ([`80651e2`](https://github.com/DevSecNinja/truenas-apps/commit/80651e2ffe391599bfcadf6d9c03174db0093837))
- Update github/codeql-action action to v4 ([`cf2dc84`](https://github.com/DevSecNinja/truenas-apps/commit/cf2dc843f81de77406585c117ab7d1a76659ff62))
- Add actionlint, gitleaks, and zizmor jobs to CI workflows ([`425f875`](https://github.com/DevSecNinja/truenas-apps/commit/425f8750cf987d44eca4e18c4847aeca8859efdf))
- Update actions/checkout action to v4.3.1 ([`6f8ff1e`](https://github.com/DevSecNinja/truenas-apps/commit/6f8ff1ee6935fcca14621834780afefb4b8990ec))

### Documentation

- **architecture**: Enforce cap_drop: ALL requirement for all containers ([`ffb586e`](https://github.com/DevSecNinja/truenas-apps/commit/ffb586ec993cd55d43c4b9fd0f22032a09b0620b))
- **readme**: Add references to DevSecNinja/home and GitHub Copilot in README.md ([`b88c104`](https://github.com/DevSecNinja/truenas-apps/commit/b88c1046d5db7ad8c9eabb8829191a3317b8df4d))

### Features

- **traefik-forward-auth**: Add Traefik Forward Auth service with init container for config substitution and update middleware chains ([`ee27ae9`](https://github.com/DevSecNinja/truenas-apps/commit/ee27ae9ad5af8fcf9e6fceb31398c384299f645f))
- **adguard,echo-server**: Add capability adjustments to services for enhanced security and ownership management ([`0123ddb`](https://github.com/DevSecNinja/truenas-apps/commit/0123ddb09b248bab9369172900e9ef89a263f253))
- **homepage,shared**: Add init container for homepage to manage volume permissions and create shared env file ([`309bdad`](https://github.com/DevSecNinja/truenas-apps/commit/309bdadfae1b5efe71d89f7df1c9d378c3849d2b))
- **architecture,traefik**: Add init container for traefik to manage volume permissions ([`885f361`](https://github.com/DevSecNinja/truenas-apps/commit/885f3618461801c5b9d7a167c9d3df54e25b06ac))
- **tooling**: Add EditorConfig and VSCode settings for consistent code formatting ([`003dee1`](https://github.com/DevSecNinja/truenas-apps/commit/003dee121731fe03b65998a17fc528b6a81458ec))
- **mise,renovate**: Add Renovate datasource support for .mise.toml and update regex patterns in renovate.json ([`24a98a9`](https://github.com/DevSecNinja/truenas-apps/commit/24a98a914e58a8420d4e20f2fb76610a0ffceb97))
- **renovate**: Add GitHub Actions lint workflow and update Renovate configuration for YAML files ([`beb7c87`](https://github.com/DevSecNinja/truenas-apps/commit/beb7c87d8e597b48f5d4435160d0da7c9dc46dfe))
- **lefthook**: Add ShellCheck configuration and update YAML formatting commands ([`3e0e4fb`](https://github.com/DevSecNinja/truenas-apps/commit/3e0e4fb031fd19f716fdf4d38a2d7603077589da))
- **lefthook,mise**: Add Lefthook configuration for YAML formatting ([`12cf20e`](https://github.com/DevSecNinja/truenas-apps/commit/12cf20edfce397cafdc59c1ce5413bf7468345a3))
- **mise,yamlfmt**: Add yamlfmt configuration file and update tools section in .mise.toml ([`b7389b1`](https://github.com/DevSecNinja/truenas-apps/commit/b7389b1426eecdca0ed71b40636f9819926c7a59))

### Miscellaneous

- **deps**: Update postgres to v17.9 ([`7c1f6fb`](https://github.com/DevSecNinja/truenas-apps/commit/7c1f6fbecf2cd2e19b7f35412e2b15373aff7793))
- **deps**: Update dependency jdx/mise to v2026.3.17 ([`1b3351a`](https://github.com/DevSecNinja/truenas-apps/commit/1b3351a1044e5cc5953ff5e542c792847dab67a7))
- **renovate**: Group postgres and pgautoupgrade together ([`268f4a5`](https://github.com/DevSecNinja/truenas-apps/commit/268f4a5ff1404da09af12bb736654bc4d1891f91))
- **renovate**: Group jdx/mise together in Renovate config ([`4c608e1`](https://github.com/DevSecNinja/truenas-apps/commit/4c608e1ead9c0b6538258deeaf42a304a9b26768))
- **deps**: Pin jdx/mise-action action to 1648a78 ([`ab5c1d5`](https://github.com/DevSecNinja/truenas-apps/commit/ab5c1d5625a7f228d75a47140ff6581e738ae4ab))
- **adguard,dccd**: Autofix shellcheck: refactor variable expansion in envsubst.sh for consistency ([`91a6292`](https://github.com/DevSecNinja/truenas-apps/commit/91a62925390501a454e3c131cabcdf79834391ec))

### Other

- Apply yamlfmt formatting recommendations across YAML files ([`f910272`](https://github.com/DevSecNinja/truenas-apps/commit/f9102728799171ac7b5b1e6ba249f9bb54e3f5aa))

## [0.5.0] - 2026-03-28

### Bug Fixes

- **gatus**: Remove AdGuard DNS endpoints from configuration ([`702c0e5`](https://github.com/DevSecNinja/truenas-apps/commit/702c0e5679b1345a0d10efb2d877b2fda5ee3f30))
- **adguard,architecture**: Update architecture documentation and adjust unbound service configuration for runtime directory creation ([`9f1cbe2`](https://github.com/DevSecNinja/truenas-apps/commit/9f1cbe2d8b4b0bc7a477f7269470fc9384e27f11))
- **gatus**: Update endpoint defaults: change interval to 1m and timeout to 3s ([`7a88676`](https://github.com/DevSecNinja/truenas-apps/commit/7a8867680fa16b07c768e23349c318870d15a9d6))
- **gatus**: Comment out unused HTTP endpoints in config.yaml for clarity ([`57dc2f2`](https://github.com/DevSecNinja/truenas-apps/commit/57dc2f25fa171b7aeba811c6e59c4ccaba7fe418))

### Features

- **gatus**: Add AdGuard DNS endpoints for local and external health checks ([`f41e997`](https://github.com/DevSecNinja/truenas-apps/commit/f41e997408fbccd978c622c7ce8bba2ebfc589be))
- **adguard**: Add healthcheck canary to verify unbound configuration loading ([`3b08050`](https://github.com/DevSecNinja/truenas-apps/commit/3b08050fd7d9b3b0c433147b561751749a5d5cf2))
- **adguard**: Add adguard-init service to set ownership on data volume and configuration directory ([`7553189`](https://github.com/DevSecNinja/truenas-apps/commit/75531894fbbf00a2616884c8bd44c0835992b3e6))
- **adguard,traefik**: Add AdGuard Home configuration and integrate with Traefik ([`0191c96`](https://github.com/DevSecNinja/truenas-apps/commit/0191c96b4a0602109064ef18acd3e9c66c3fe98d))
- **gatus**: Add UniFi TCP/UDP endpoints and update alert descriptions in config.yaml ([`2c4146a`](https://github.com/DevSecNinja/truenas-apps/commit/2c4146a60d6fa67b7f5cb5c18586c2f83e640d1e))
- **dccd**: Add logging for successful pull from remote repository in update_compose_files function ([`f614f7b`](https://github.com/DevSecNinja/truenas-apps/commit/f614f7bef73496a061b43a0a9a6588a86d9f088f))

### Miscellaneous

- **deps**: Pin docker.io/library/busybox Docker tag to 1487d0a ([`8f44596`](https://github.com/DevSecNinja/truenas-apps/commit/8f44596de0a4a5ecd3b5267f2f44b211b6f28f03))

### Refactoring

- **gatus**: Gatus service to use configs for configuration file ([`1f945a0`](https://github.com/DevSecNinja/truenas-apps/commit/1f945a02292a665541dcda070fe498af6bed69ab))

## [0.4.0] - 2026-03-28

### Bug Fixes

- **dccd**: Using -prune makes find skip the directory entirely without attempting to descend into it ([`8cfe073`](https://github.com/DevSecNinja/truenas-apps/commit/8cfe07345098ffbc9adc81f4c0d6665ce20ad69c))
- **gitignore**: Update .gitignore to include comments for clarity on ignored files ([`33ca2b9`](https://github.com/DevSecNinja/truenas-apps/commit/33ca2b98af071b0bd0bc261fa0f0e65ae210f676))

### Features

- **traefik,unifi**: Add insecure-skip-verify transport for Unifi HTTPS connections ([`b2c65bf`](https://github.com/DevSecNinja/truenas-apps/commit/b2c65bf2b370ece18230efdf09113ba491f573d4))
- **traefik,unifi**: Add Unifi service configuration and update architecture documentation ([`50277e8`](https://github.com/DevSecNinja/truenas-apps/commit/50277e8e4f769e61abb5f313281f45dab46b21fc))

### Miscellaneous

- **deps**: Update twinproduction/gatus Docker tag to v5.35.0 ([`a1754b6`](https://github.com/DevSecNinja/truenas-apps/commit/a1754b61224c78e515c41052678788935d51a9a3))
- **dccd**: Exclude data and backups directories from SOPS and compose file searches ([`460e841`](https://github.com/DevSecNinja/truenas-apps/commit/460e8411f0db48fbebe1bcc6be9c7d7593b5bb8d))
- **adguard,echo-server**: Remove empty .gitkeep files from various service directories ([`da58aad`](https://github.com/DevSecNinja/truenas-apps/commit/da58aad13d1c04f53e711bb777f3134b7673ea2c))

### Refactoring

- **gitignore**: .gitignore to simplify data and backups exclusion rules ([`45980c1`](https://github.com/DevSecNinja/truenas-apps/commit/45980c1dc3f4fe912787d0dbafaecaa68ee56104))

## [0.3.0] - 2026-03-28

### Bug Fixes

- **gatus**: Update gatus-db-backup configuration for user handling and clarify comments ([`8aff8a6`](https://github.com/DevSecNinja/truenas-apps/commit/8aff8a6c499f965ecf6e1895197632b3639d431b))
- **gatus**: Remove healthcheck from Gatus service due to scratch-based image limitations ([`ba3f632`](https://github.com/DevSecNinja/truenas-apps/commit/ba3f6323788df03aca4e1378218156bac892d5f0))
- **traefik**: Remove TODO comments from Content-Security-Policy in middlewares.yml for clarity ([`0629eae`](https://github.com/DevSecNinja/truenas-apps/commit/0629eae5ee1e56354fe9b98e68d977081bfa061e))
- **traefik**: Uncomment Content-Security-Policy in middlewares.yml for improved security ([`fefd82c`](https://github.com/DevSecNinja/truenas-apps/commit/fefd82cf231cf04cb845351fee24ade456871495))
- **traefik**: Comment out Content-Security-Policy in middlewares.yml for further testing ([`2f088c6`](https://github.com/DevSecNinja/truenas-apps/commit/2f088c6bb05cb51dcd454a7ece3c92c67e971fde))
- **traefik**: Uncomment Content-Security-Policy in middlewares.yml for improved security ([`0a7643f`](https://github.com/DevSecNinja/truenas-apps/commit/0a7643f5be2f4a67aaaa54b9105e0f29b47d098a))
- **dccd**: Set permissions on decrypted secret environment files for enhanced security ([`4a7f36f`](https://github.com/DevSecNinja/truenas-apps/commit/4a7f36f15c228c9b56d2350678534d29d8cf3ffd))
- **traefik**: Adjust rate limit settings in middlewares.yml for improved performance and security; add Content-Security-Policy header for enhanced protection ([`8bc01bd`](https://github.com/DevSecNinja/truenas-apps/commit/8bc01bd76ba8fb8cdc6610a2503c4b33ed5b95e2))
- **echo-server,homepage**: Enhance echo-server and homepage services with read-only file system and tmpfs for /tmp; update Traefik access log status codes to include 599 ([`a792dc9`](https://github.com/DevSecNinja/truenas-apps/commit/a792dc9bc8c5427a7fefc2908208e1a9cbaae1c3))
- **dccd**: Enhance dccd.sh script by adding error handling and initializing SOPS binary path ([`74ed07b`](https://github.com/DevSecNinja/truenas-apps/commit/74ed07b28af3bd424144f74f5a1276eb3c0f4af6))
- **traefik**: Update traefik volume configuration to set rules directory as read-only ([`b24a75f`](https://github.com/DevSecNinja/truenas-apps/commit/b24a75ffc6b43761d7ad265e3a975a63c5d150b3))
- **traefik**: Remove TODO comment regarding data and config folder ownership in traefik service configuration ([`f292902`](https://github.com/DevSecNinja/truenas-apps/commit/f2929026c775ce65ee5ba354c5ad882996c2ddd4))
- **traefik**: Uncomment user line in traefik service configuration ([`17ea50a`](https://github.com/DevSecNinja/truenas-apps/commit/17ea50ae291f3dbcdc66e84d84c3aa479fda3745))
- **traefik**: Comment out caServer line in traefik.yml for LetsEncrypt staging server ([`2f839ea`](https://github.com/DevSecNinja/truenas-apps/commit/2f839eaf4239167932e6ebd2530b96f1aadae866))
- **traefik**: Update traefik volume configuration and uncomment caServer in traefik.yml ([`546670d`](https://github.com/DevSecNinja/truenas-apps/commit/546670d2e1e9b8fbe27945304c7b023d00e7402a))
- **echo-server,homepage**: Reduce healthcheck intervals for echo-server, homepage, and traefik services from 30s to 15s and 5s for specific checks ([`b81023c`](https://github.com/DevSecNinja/truenas-apps/commit/b81023c8480218b57480e77730a3ee63456dfccb))
- **homepage,traefik**: Set networks for homepage and traefik as internal ([`a73b334`](https://github.com/DevSecNinja/truenas-apps/commit/a73b334ac1316c190cff1a78ebe584e5ce5598c0))
- **dccd**: Improve error handling during container deployment in dccd.sh ([`cc806e8`](https://github.com/DevSecNinja/truenas-apps/commit/cc806e828ef95b54c562c1935f8242201fe589aa))
- **renovate**: Enable pinDigests in Renovate configuration ([`fb1edb8`](https://github.com/DevSecNinja/truenas-apps/commit/fb1edb85966ed8bd1c0665fca3febabf2d670695))
- **dccd**: Update default timeout for container health check to 60 seconds ([`3712de0`](https://github.com/DevSecNinja/truenas-apps/commit/3712de01db74bd39b39eb4541bd243349152510f))
- **traefik**: Force TLS 1.3 ([`0c58fc6`](https://github.com/DevSecNinja/truenas-apps/commit/0c58fc6bfa678733826d6b2e56c2537711d1f9a0))

### Documentation

- **architecture**: Add directory conventions for service layout in ARCHITECTURE.md ([`4e7ab66`](https://github.com/DevSecNinja/truenas-apps/commit/4e7ab66ee0333bdd5c50b43ac9012801aa7c480d))
- **architecture**: Add comprehensive architecture documentation outlining Compose file standards, networking isolation, and secret management ([`5b07ce4`](https://github.com/DevSecNinja/truenas-apps/commit/5b07ce427bc62e997b57196e969b18a086bdc03c))
- **readme**: Reformat benefits section in README.md for improved clarity and presentation ([`ad09259`](https://github.com/DevSecNinja/truenas-apps/commit/ad09259fe6200d523e733748b2bf2f824b309a3b))
- **readme**: Refactor benefits section in README.md for improved readability ([`29cfccd`](https://github.com/DevSecNinja/truenas-apps/commit/29cfccdecb5767f0fb1c983b0d2f6b0c56774936))
- **readme**: Add benefits section to README.md outlining key advantages of the setup ([`8dfd3cd`](https://github.com/DevSecNinja/truenas-apps/commit/8dfd3cd0f790a4195abb5180172960250d32d9dd))
- **readme**: Add homepage app to the overview and setup sections in README.md ([`5c9bc2f`](https://github.com/DevSecNinja/truenas-apps/commit/5c9bc2f77105ff8b920407a326983733e873379f))

### Features

- **gatus,traefik**: Add Gatus service configuration and update architecture documentation ([`c6d2aeb`](https://github.com/DevSecNinja/truenas-apps/commit/c6d2aebb1e744b2a4de82b62f19422a3c43ab19e))
- **traefik**: Add cap_drop directive to traefik service for enhanced security ([`814fd1f`](https://github.com/DevSecNinja/truenas-apps/commit/814fd1f2bb4366e1e0f3cba3349fd6408a013b8a))
- **echo-server,homepage**: Add pids_limit to services and update Content-Security-Policy comments for improved security and stability ([`92da8b9`](https://github.com/DevSecNinja/truenas-apps/commit/92da8b98601d61f6710641250427e95b16bd365d))
- **traefik**: Add tmpfs configuration for traefik service and ensure read-only access ([`f0656b6`](https://github.com/DevSecNinja/truenas-apps/commit/f0656b63d261e5c55363799189ca863b849adf5f))
- **echo-server**: Add healthcheck configuration for echo-server service ([`26d6ccc`](https://github.com/DevSecNinja/truenas-apps/commit/26d6ccc20f784b88b8b6326e220bd231ec9df4ca))
- **traefik**: Add ping configuration to Traefik for health checks ([`e03c7e6`](https://github.com/DevSecNinja/truenas-apps/commit/e03c7e6a7a6f394836ea5d4352a9d7bcfa104565))
- **traefik**: Add health checks for traefik and traefik-docker-proxy services ([`4067704`](https://github.com/DevSecNinja/truenas-apps/commit/40677049f19ff9bb5cd4e4bc53b1900459e6b1c5))
- **homepage**: Add health checks for homepage and homepage-docker-proxy services ([`2d4d96f`](https://github.com/DevSecNinja/truenas-apps/commit/2d4d96fe79c8acbbbd14e655f87a7dc283c22147))

### Miscellaneous

- **deps**: Update ghcr.io/gethomepage/homepage Docker tag to v1.12.1 ([`7423bd1`](https://github.com/DevSecNinja/truenas-apps/commit/7423bd1054843721b79cd1432adcf377a78aa154))
- **deps**: Pin alstr/todo-to-issue-action action to 64aca8f ([`db053df`](https://github.com/DevSecNinja/truenas-apps/commit/db053dfb3f4d0d659fde25ec29362c70e9108dfa))

### Refactoring

- **dccd**: Update_compose_files to separate Traefik and other compose files for proper deployment order ([`65cfef3`](https://github.com/DevSecNinja/truenas-apps/commit/65cfef3ecc2643bb17eb07ad0ff6246338c9b477))
- **dccd**: Logging and checksum verification in dccd.sh ([`aa2ad56`](https://github.com/DevSecNinja/truenas-apps/commit/aa2ad5698ec1c22b034fbc60defd9e237d72bd66))

## [0.2.0] - 2026-03-27

### Bug Fixes

- **homepage**: Volume path for homepage service in compose.yaml ([`af1974a`](https://github.com/DevSecNinja/truenas-apps/commit/af1974ad3b3f7aa59fd3dc14de9bb2b2d73a1b45))
- **homepage,traefik**: Remove Traefik labels from homepage-docker-proxy service and linuxserver.env from Traefik service ([`cef79d0`](https://github.com/DevSecNinja/truenas-apps/commit/cef79d0f19028af56b16b3782963b4c2d8f383fa))
- **homepage**: Remove homepage-frontend network from homepage-docker-proxy service ([`a21de17`](https://github.com/DevSecNinja/truenas-apps/commit/a21de17ba74d842860dd1f081e4a69acee2c9691))
- **traefik**: Comment out user configuration in traefik service for clarity ([`bc7a9e8`](https://github.com/DevSecNinja/truenas-apps/commit/bc7a9e86349203226b8f8dfd43366cf721593222))
- **traefik**: Remove unused compose.env file and update env_file reference in traefik compose.yaml ([`22859e3`](https://github.com/DevSecNinja/truenas-apps/commit/22859e33c0887a999acbc289d31bbb290a6508f5))
- **echo-server,traefik**: Update PUID and PGID in echo-server and traefik compose files for consistency ([`5e54c4e`](https://github.com/DevSecNinja/truenas-apps/commit/5e54c4e4163c7c70035c51d3924e985b049c1ae5))

### CI/CD

- Add GitHub workflow to convert TODOs to issues on push ([`d0ce7c4`](https://github.com/DevSecNinja/truenas-apps/commit/d0ce7c45e57856b84c1f525ee8824751beda0ffd))

### Features

- **echo-server,traefik**: Add homepage description labels for Echo-Server and Traefik services ([`76018e1`](https://github.com/DevSecNinja/truenas-apps/commit/76018e1a32c1bfe08346a446252a2d9d3f12d394))
- **traefik**: Add homepage-frontend network to traefik service ([`deab8fa`](https://github.com/DevSecNinja/truenas-apps/commit/deab8fa8345939a1e133c2cbdb2cf5238d692306))
- **echo-server,homepage**: Add homepage service configuration and related files ([`2d90427`](https://github.com/DevSecNinja/truenas-apps/commit/2d904277e451a24e71c60bfd03034b886aa9737e))
- **traefik**: Add SVLNAS redirect rules to Traefik configuration ([`a26f268`](https://github.com/DevSecNinja/truenas-apps/commit/a26f2689e76a94c3662e04b6669b68e3b5f49841))

### Miscellaneous

- **deps**: Update ghcr.io/gethomepage/homepage Docker tag to v1.11.0 ([`d893986`](https://github.com/DevSecNinja/truenas-apps/commit/d893986bfeb39a425e4c2b7981a23ad50e498552))
- **gitignore,homepage**: Add proxmox config placeholder ([`979cff4`](https://github.com/DevSecNinja/truenas-apps/commit/979cff4764586ea79093600f680c0531a792a773))
- **adguard,gatus**: Add placeholder folders for new apps ([`a26fc96`](https://github.com/DevSecNinja/truenas-apps/commit/a26fc96c49914dd809f0580af7a785464d52015d))
- **traefik**: Add TODO comment for resolving ownership issues in data and config folders ([`a52e728`](https://github.com/DevSecNinja/truenas-apps/commit/a52e72806797723a67b39aed10bae44fd613ef75))

## [0.1.0] - 2026-03-26

### Bug Fixes

- **dccd**: Enhance logging in log_image_changes function to improve clarity of deployment results ([`730aaa7`](https://github.com/DevSecNinja/truenas-apps/commit/730aaa7c470c0f068928f3bbaa0ab680eae29f34))
- **traefik**: Update CF_DNS_API_TOKEN and metadata in secret.sops.env ([`08680fe`](https://github.com/DevSecNinja/truenas-apps/commit/08680fe32db2365322dc9d3d0ecd980cbedc08ad))
- **echo-server,traefik**: Update environment variable files to use .env and add comments for clarity ([`bc672f6`](https://github.com/DevSecNinja/truenas-apps/commit/bc672f6d50d290454063bb90d3552f1f7dd1e311))
- **traefik**: Use production Lets Encrypt and update accessLog statusCodes to list ([`b2317fd`](https://github.com/DevSecNinja/truenas-apps/commit/b2317fdaf990a1ada43dcbba5e22dcaebd0882f2))
- **dccd,traefik**: Update environment variable references to use .env instead of secret.env ([`a9486d3`](https://github.com/DevSecNinja/truenas-apps/commit/a9486d3cc6fd1586ef33fed9fc343e2456ab48e2))
- **traefik**: Remove HOST_HTTP_PORT and HOST_HTTPS_PORT from traefik compose environment ([`4332885`](https://github.com/DevSecNinja/truenas-apps/commit/4332885f141ecf5a215f37064e4ae89e14e15578))
- **dccd**: Update decryption function to handle all *.sops.env files ([`1a78ea3`](https://github.com/DevSecNinja/truenas-apps/commit/1a78ea3d3221e2b12ad7260f9f223ecc812350b0))
- **dccd**: Update SOPS installation directory handling in dccd.sh ([`4f88cab`](https://github.com/DevSecNinja/truenas-apps/commit/4f88cab98d1fa1ffa2a6730d0c688ab263296bec))
- **dccd**: Improve error handling for SOPS binary installation in dccd.sh ([`e1c9c59`](https://github.com/DevSecNinja/truenas-apps/commit/e1c9c591fe51d49db66143393082952439fe0b30))
- **echo-server**: Update environment variable references in echo-server configuration ([`2d44ea1`](https://github.com/DevSecNinja/truenas-apps/commit/2d44ea15595555adddafa943c9246322f245dc13))
- **dccd**: Log message formatting for excluded apps in redeploy function ([`534dbc7`](https://github.com/DevSecNinja/truenas-apps/commit/534dbc7601da5724e8597029d4e7d784a69a682d))
- **dccd**: Update usage comment for TrueNAS Scale ([`d209900`](https://github.com/DevSecNinja/truenas-apps/commit/d209900a1c5e1d7aae4b1522f6c62aa1789955fa))
- **dccd**: Update dccd.sh with usage instructions ([`0a984f1`](https://github.com/DevSecNinja/truenas-apps/commit/0a984f19798cece63689931289a5967e0dd2acee))
- **dccd**: Update log file name to include username for per-user logging ([`79a8108`](https://github.com/DevSecNinja/truenas-apps/commit/79a810810fe7cbfc519cf304b715f744be2878e4))
- **dccd**: Make sudo conditional ([`ddd2e46`](https://github.com/DevSecNinja/truenas-apps/commit/ddd2e46b7c18bbf30c8956ea3265ce07e6d00656))
- **dccd**: Stderr redirection to log file for improved error logging ([`2aa2191`](https://github.com/DevSecNinja/truenas-apps/commit/2aa21917450ef5ce3cfb9a17ae217e9b027d5bb6))
- **dccd**: Add sudo to docker call ([`b870226`](https://github.com/DevSecNinja/truenas-apps/commit/b870226f6723f606e20991ce131e335d2cb0c3b7))
- **dccd**: Add sudo command to prune ([`c3382e0`](https://github.com/DevSecNinja/truenas-apps/commit/c3382e09971071871ced31d165d688a254330d74))

### Documentation

- **readme**: Update acknowledgments in README.md to include additional projects and their roles ([`dfef1bd`](https://github.com/DevSecNinja/truenas-apps/commit/dfef1bd5cde53b9e4ceb00b72a41e611f059e866))
- **readme**: Update README.md for improved clarity and structure; add TrueNAS logo ([`be63ad6`](https://github.com/DevSecNinja/truenas-apps/commit/be63ad68b3a9725e4ccb1f2c398004cd2ceeb2de))
- **readme**: Add initial README.md with project overview, setup instructions, and acknowledgments ([`3f45314`](https://github.com/DevSecNinja/truenas-apps/commit/3f45314e57d231cb4f1ea7682b59a462e2747013))

### Features

- **dccd**: Add functions to log Docker image changes during redeployment ([`9781385`](https://github.com/DevSecNinja/truenas-apps/commit/978138596a924f8196a08c991aca4935bb92c5dd))
- **dccd**: Add wait timeout option for redeploying TrueNAS apps ([`2903512`](https://github.com/DevSecNinja/truenas-apps/commit/29035122ab8f90354f22f14d48021c70f7af0bc1))
- **echo-server,traefik**: Add Traefik configuration for echo-server and define external network ([`594dd64`](https://github.com/DevSecNinja/truenas-apps/commit/594dd64d9bbb20887de6e371bf8848bfb431ab7a))
- **mise,traefik**: Add Traefik configuration files and environment setup ([`1fa8a5b`](https://github.com/DevSecNinja/truenas-apps/commit/1fa8a5bc78e77bf58443baf5abf9b2f5003ad607))
- **dccd**: Add SOPS_AGE_KEY_FILE support for Age private key in dccd.sh ([`94d6840`](https://github.com/DevSecNinja/truenas-apps/commit/94d684003585cb7ecbdb5e7ba57aa580f2c9d006))
- **echo-server,gitignore**: Add encrypted secrets to secret.sops.env and update .gitignore ([`eb1c274`](https://github.com/DevSecNinja/truenas-apps/commit/eb1c2742976d392e756b6ed2c0b538ad563146b0))
- **dccd**: Add support for custom SOPS installation directory in dccd.sh ([`285d583`](https://github.com/DevSecNinja/truenas-apps/commit/285d583b5d379867a442781747774f679852ff03))
- **dccd**: Add logging for missing SOPS files and restore ownership in update_compose_files ([`446cd71`](https://github.com/DevSecNinja/truenas-apps/commit/446cd7186c192d2b7dd8114d660f3a3fd9a5f612))
- **dccd,renovate**: Add SOPS support for secret decryption and update configuration files ([`3f346ad`](https://github.com/DevSecNinja/truenas-apps/commit/3f346ad7413be2f8fe5cce72c505cdb76fcdfd56))
- **echo-server**: Add user environment variables for echo-server configuration ([`8a5662d`](https://github.com/DevSecNinja/truenas-apps/commit/8a5662d4fec91c1ca39b6c2b1ec77442fb193817))
- **echo-server**: Add environment variable files for echo-server configuration ([`ff5862c`](https://github.com/DevSecNinja/truenas-apps/commit/ff5862c355ccdde0565aa6ce30f2bee349ba3ec8))
- **dccd**: Add support for HTTPS Git URLs in update_compose_files function ([`154a961`](https://github.com/DevSecNinja/truenas-apps/commit/154a961747e98068ef9fd4d8e9d442b321458f1a))
- **dccd**: Add FORCE option to skip hash check during redeploy ([`a3007c2`](https://github.com/DevSecNinja/truenas-apps/commit/a3007c2567b358174506b914c260266ecdd835ef))
- **dccd**: Implement TrueNAS Scale mode for app deployment in dccd.sh ([`31bcd82`](https://github.com/DevSecNinja/truenas-apps/commit/31bcd82ee00ce2239c48384e99dec663e595959f))
- **dccd**: Add Cont Deployment script for Docker ([`358956d`](https://github.com/DevSecNinja/truenas-apps/commit/358956d53913da04d7e8f1ee7cc4977ef62dfda8))
- **renovate**: Add renovate.json ([`96565fa`](https://github.com/DevSecNinja/truenas-apps/commit/96565fa590bc12be9de7d55010540bd4f7f48a8d))
- **echo-server**: Add basic echo-server app ([`468807a`](https://github.com/DevSecNinja/truenas-apps/commit/468807a07177b67fc83d0c7dc08ffed6ef7ceef6))
- Add license ([`03c2d76`](https://github.com/DevSecNinja/truenas-apps/commit/03c2d767637a74e004dfccf09b0f699901bc9a44))

### Miscellaneous

- **deps**: Update traefik Docker tag to v3.6.12 ([`4b24140`](https://github.com/DevSecNinja/truenas-apps/commit/4b24140826ec94f8a65919e48c02d4ecded132c7))
- **gitignore**: Ignore bin dir ([`da981b3`](https://github.com/DevSecNinja/truenas-apps/commit/da981b3d70cb3c71e114053dc537e168335d1f99))
- **echo-server**: Add empty sops file for testing ([`c9b26cd`](https://github.com/DevSecNinja/truenas-apps/commit/c9b26cd42442d410f9721128f868b8cd6197d576))
- **echo-server**: Add .gitkeep file to echo-server config directory ([`7c2e2b4`](https://github.com/DevSecNinja/truenas-apps/commit/7c2e2b4604d69c5387a528e8067b82b0d8774c84))
- **dccd**: Redirect stderr to log file for better error tracking ([`83d6a12`](https://github.com/DevSecNinja/truenas-apps/commit/83d6a12122dc93ff66fc85f8949784b2a6b80040))
- **deps**: Update mendhak/http-https-echo Docker tag to v40 ([`e0e4c69`](https://github.com/DevSecNinja/truenas-apps/commit/e0e4c698f7f96fbd78b3da935915ac456754b5ff))
- **deps**: Update mendhak/http-https-echo Docker tag to v40 ([`39d4e0e`](https://github.com/DevSecNinja/truenas-apps/commit/39d4e0eb625d911e84129df0b7791ba405cba339))

### Other

- **deps**: Revert "Update mendhak/http-https-echo Docker tag to v40" ([`8e54216`](https://github.com/DevSecNinja/truenas-apps/commit/8e5421648b7db2cecbf9dd344f96e439bfdaeba1))

### Refactoring

- **dccd**: Get_project_image_info function to improve image retrieval using docker inspect ([`b060f3b`](https://github.com/DevSecNinja/truenas-apps/commit/b060f3be704002a6843bcdd0152750fbd09eee44))
- **vscode**: VSCode settings to enhance file management and exclusion patterns ([`d713327`](https://github.com/DevSecNinja/truenas-apps/commit/d713327b68ad860efedb4f8934b01685c351ea6f))
- **renovate**: Migrate config renovate.json ([`858d028`](https://github.com/DevSecNinja/truenas-apps/commit/858d028d5b28286f27a684f8b538ffa13586eacd))
- **dccd,echo-server**: Environment variable files and update usage instructions for echo-server ([`a3aa1fb`](https://github.com/DevSecNinja/truenas-apps/commit/a3aa1fb205a1787f08af390efdc034a2169866b4))
