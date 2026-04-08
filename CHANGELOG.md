# Changelog

All notable changes to this project will be documented in this file.

## [0.11.0] - 2026-04-08

### Bug Fixes

- **cog**: Limit changelog to v0.10.0 onwards ([`efb7b86`](https://github.com/DevSecNinja/truenas-apps/commit/efb7b86a8f6256b28a285272f6c9f8f1511b9b6f))
- **aliases**: Update dps alias to include sorting of container health status ([`cc1f184`](https://github.com/DevSecNinja/truenas-apps/commit/cc1f1844ea5e3150a5c6419d05bf2c63f9a7bf00))
- **compose**: Add arr-stack-backend service to the arr-egress network configuration ([`a83e097`](https://github.com/DevSecNinja/truenas-apps/commit/a83e0975551299110ef07eb43ac8a5135e44ef28))
- **arr**: Simplify arr stack networking ([`6defd29`](https://github.com/DevSecNinja/truenas-apps/commit/6defd29404d661079a160a0cb5c11e55594cfb95))
- **compose**: Update arr-stack-backend network configuration to use bridge driver and set internal access ([`0b3fdb3`](https://github.com/DevSecNinja/truenas-apps/commit/0b3fdb3e937cc681f8da2fb19f2f4d3878d409be))

### CI/CD

- Add automated release pipeline with git-cliff and cog ([`6cc2242`](https://github.com/DevSecNinja/truenas-apps/commit/6cc2242285f507086bb7d65c796619e63f5c6999))

### Features

- **pre-commit**: Add sops-encryption-check command to validate SOPS encryption ([`5bfb02d`](https://github.com/DevSecNinja/truenas-apps/commit/5bfb02d6d23c836cd8ddf3512b5b914ce0318c3b))
- **arr**: Add the rest of the arr stack (excl. Traefik networks) ([`4c0ad67`](https://github.com/DevSecNinja/truenas-apps/commit/4c0ad671d53be31d29374e8fb052b439385353f4))

## [0.10.0] - 2026-04-07

### Bug Fixes

- **renovate**: Refine update timing policy for GitHub Actions and clarify auto-merge requirements ([`eb50d98`](https://github.com/DevSecNinja/truenas-apps/commit/eb50d988e2ac85c6ac0823b83cabcc98d1ab45d3))
- **renovate**: Update package rules for dependency management and improve configuration clarity ([`eb0f3fb`](https://github.com/DevSecNinja/truenas-apps/commit/eb0f3fb053ac022bfbb8ed6333de2b32bd925a82))
- **mise**: Add cocogitto tool and update version to 7.0.0 in configuration ([`0b48a06`](https://github.com/DevSecNinja/truenas-apps/commit/0b48a068abcd373bcf55f2e08edef08fcb4db25b))
- **database**: Update gatus-db restart policy to on-failure with max attempts for improved stability ([`97f1d11`](https://github.com/DevSecNinja/truenas-apps/commit/97f1d1148b9bf59ca0a018bd10191b8965385bcc))
- **services**: Update restart policy to on-failure with max attempts for improved stability ([`4148995`](https://github.com/DevSecNinja/truenas-apps/commit/4148995619051b8be275c595687d5f3cc78f2526))
- **immich**: Update mobile app endpoint and OAuth configuration for improved authentication flow ([`a5932d3`](https://github.com/DevSecNinja/truenas-apps/commit/a5932d34e1c3373399f246ed04324375d3348e50))
- **dccd**: Enhance Gatus reporting with DNS resolution and improved error logging ([`f38fa21`](https://github.com/DevSecNinja/truenas-apps/commit/f38fa2154f06bdca5982e97b2941ab6e05ca9aaf))
- **echo-server, metube**: Update restart policy to on-failure with max attempts ([`43d5cae`](https://github.com/DevSecNinja/truenas-apps/commit/43d5cae6013cb7158c52eddcfeae6ea5d83136fc))
- **gatus**: Update alert configurations to enable custom alert types and correct DNS endpoint URLs ([`814d3a4`](https://github.com/DevSecNinja/truenas-apps/commit/814d3a45d519d35224fbfd1ff3380721b423d94f))
- **immich**: Add App Roles configuration for admin/user assignment via Entra token ([`88ecc6a`](https://github.com/DevSecNinja/truenas-apps/commit/88ecc6a562dabd5132aeed5d5e0da560754e9290))
- **immich**: Update roleClaim in OAuth configuration from 'immich_role' to 'roles' ([`261cbdb`](https://github.com/DevSecNinja/truenas-apps/commit/261cbdbbe250b00891644abe532dd16f621161e2))
- **immich**: Enable autoLaunch for OAuth and disable password login ([`4a0f6d4`](https://github.com/DevSecNinja/truenas-apps/commit/4a0f6d490a70985124ed404cabbaf26e8541aafb))
- **gatus**: Update DNS server references to use IP_ROUTER for endpoint configurations ([`94bbf0d`](https://github.com/DevSecNinja/truenas-apps/commit/94bbf0dee5587b7066afc62c12771f727b66c719))
- **dccd**: Enhance Gatus DNS server handling with fallback mechanism ([`11c2a07`](https://github.com/DevSecNinja/truenas-apps/commit/11c2a07b2bcc9f6c3be64ef080f37f626e106aa2))
- **immich**: Streamline ownership handling in Docker Compose and update README for storage layout ([`4ebe516`](https://github.com/DevSecNinja/truenas-apps/commit/4ebe516eb4e16e3890fde2a7c8b99bd1fba66633))
- **immich**: Improve ownership handling in init script and documentation ([`ac756b4`](https://github.com/DevSecNinja/truenas-apps/commit/ac756b40ecd35ae3b91cf83e32431863e9c560e7))
- **immich**: Correct comment formatting in configuration template ([`70bb0a4`](https://github.com/DevSecNinja/truenas-apps/commit/70bb0a420720c80f84c2d19ccefe95def54934e0))
- **gatus**: Optimize config file copy to avoid unnecessary overwrites ([`d6c236f`](https://github.com/DevSecNinja/truenas-apps/commit/d6c236f165fba41f4c5760e997aed65fadc51081))
- **radarr**: Correct environment variable name for stable MAC address in compose file ([`2deb482`](https://github.com/DevSecNinja/truenas-apps/commit/2deb48262df34b2d56fbffb3e61bf9d3edb27c1f))
- **adguard**: Update A records to point to SVLNAS for various services ([`1efe2a6`](https://github.com/DevSecNinja/truenas-apps/commit/1efe2a685785f7589bb5356e7298eb23bc5c9ec1))
- **plex**: Update setup instructions for enabling Remote Access and specifying public port ([`3b36657`](https://github.com/DevSecNinja/truenas-apps/commit/3b3665792bef3fd5cd862a399b27365613857b49))
- **dccd**: Remove unnecessary ownership restoration code in update_compose_files function ([`37d1139`](https://github.com/DevSecNinja/truenas-apps/commit/37d11399e3f5130054994d8fcb76af827403beb8))
- **adguard**: Add Cloudflare DNS addresses to AdGuard configuration ([`b8aaa25`](https://github.com/DevSecNinja/truenas-apps/commit/b8aaa2562204a0c543bd0f526930a33392ac0842))
- **plex**: Update backup directory configuration in Plex settings and volume mounts ([`9a9d39e`](https://github.com/DevSecNinja/truenas-apps/commit/9a9d39e933e7d3b3e4f4273e29c0d210a4e1393a))
- **dccd**: Improve git update logic with concise logging and quiet checkout ([`05de6f2`](https://github.com/DevSecNinja/truenas-apps/commit/05de6f2522acfadf4210163baf53d6454e3a5faa))
- **plex**: Simplify media mount points by consolidating into a single directory ([`555c7fb`](https://github.com/DevSecNinja/truenas-apps/commit/555c7fb2b1486eaf981e934794ab35eb71781307))
- **dccd**: Enhance deployment logic for bootstrap projects to run in foreground ([`89b4ee1`](https://github.com/DevSecNinja/truenas-apps/commit/89b4ee177a8d801fee16a07cd3f476a4eb4f290a))
- **dccd**: Adjust app name handling to remove leading underscores for TrueNAS compatibility ([`888b265`](https://github.com/DevSecNinja/truenas-apps/commit/888b26544a4ddbcd499a274e76d9694dbcc4e63b))
- **immich**: Re-enable hardware acceleration for transcoding service ([`e732815`](https://github.com/DevSecNinja/truenas-apps/commit/e732815c99f8130c5103919e55c89cb1d7a7f1b9))
- **architecture**: Update group permissions and references for media datasets ([`b90c6c2`](https://github.com/DevSecNinja/truenas-apps/commit/b90c6c2f8afca2f3eaebb8fdd52b4c75c4ca1445))
- **gatus**: Update external endpoint configuration to use public DNS resolver and add certificate expiration check ([`916ea0e`](https://github.com/DevSecNinja/truenas-apps/commit/916ea0e5793c29ac364f191cfa72818564d1bd9e))
- **gatus**: Update DNS resolver timeout and add IP_DNS_SERVER_1 variable ([`5db43af`](https://github.com/DevSecNinja/truenas-apps/commit/5db43af636c24903531326a9ba5aff88b8fbcf5d))
- **adguard**: Add forward-tls-upstream to DDNS and V60 forward zones ([`6135eba`](https://github.com/DevSecNinja/truenas-apps/commit/6135ebad58739eedbd8c57b8dd552f5db8b7c432))
- **devcontainer**: Add SSH_AUTH_SOCK to remote environment and update mounts ([`aba50f8`](https://github.com/DevSecNinja/truenas-apps/commit/aba50f832391373afc0ebfcff9ff0eabf58a140f))
- **immich**: Update Postgres volume path for new postgresql ([`ca50458`](https://github.com/DevSecNinja/truenas-apps/commit/ca5045836ed32e4ad350ce85a3d861636708d527))
- **adguard**: Revert & comment out Cloudflare DNS addresses in fallback and forward zones ([`da4fbc1`](https://github.com/DevSecNinja/truenas-apps/commit/da4fbc19100d2f59acac980819c7a9ddc967883f))
- **adguard**: Add Cloudflare DNS addresses to forward zones configuration to improve stability ([`a117c50`](https://github.com/DevSecNinja/truenas-apps/commit/a117c5006a11b7e6bf4071f33e4c2dc5e670d8a1))
- **dccd**: Comment out ownership restoration logic as it's handled by init containers ([`97261b6`](https://github.com/DevSecNinja/truenas-apps/commit/97261b6976dff29af581e729d44f80b7926b9490))

### Documentation

- **architecture**: Add commit message convention section with guidelines ([`a5bb0e4`](https://github.com/DevSecNinja/truenas-apps/commit/a5bb0e48581430db40554eec273616d86b91c5a7))

### Features

- **renovate**: Add automerge label and update auto-merge rules for GitHub Actions ([`f10c711`](https://github.com/DevSecNinja/truenas-apps/commit/f10c711beba89f41682391b9404a4a03aac0d09a))
- **renovate**: Add package rules for dependency management and custom versioning ([`e0fc256`](https://github.com/DevSecNinja/truenas-apps/commit/e0fc25694188254f4b5b38a99b7a0d0246b935cc))
- **renovate**: Add new configuration files for Renovate, including autoMerge, customManagers, groups, labels, and semanticCommits ([`700ba23`](https://github.com/DevSecNinja/truenas-apps/commit/700ba23665081b9c37310e43662338218f3d83fe))
- **adguard**: Add A record for photos-noauth service ([`2f88abc`](https://github.com/DevSecNinja/truenas-apps/commit/2f88abce0c894b9938a4fd57135b29b404a40404))
- **immich**: Add initial README, configuration files, and envsubst script for deployment ([`d6a3429`](https://github.com/DevSecNinja/truenas-apps/commit/d6a3429b8ca46844abc09f2f2d196cf6f92a54b2))
- **dccd**: Add GATUS_DNS_SERVER option for custom DNS in Gatus curl calls ([`f7a12c2`](https://github.com/DevSecNinja/truenas-apps/commit/f7a12c2860a519eaa4fef8d06f1799ff5ed959f1))
- **gatus**: Add custom alert configuration with webhook support ([`ee26f03`](https://github.com/DevSecNinja/truenas-apps/commit/ee26f03c1240ac9c7f3c36a23566186cbb780c31))
- **aliases**: Add alias for viewing recent dccd cron job logs ([`1e7e6e9`](https://github.com/DevSecNinja/truenas-apps/commit/1e7e6e9bf0c66822129ab548a65b97ed30a46f85))
- **gatus**: Enable /events stream access for gatus-sidecar in compose file ([`2a1fcef`](https://github.com/DevSecNinja/truenas-apps/commit/2a1fcef32708a2f2b4cce03379dfdac785f16e66))
- **radarr**: Add stable MAC address variables for Radarr service configuration ([`780038e`](https://github.com/DevSecNinja/truenas-apps/commit/780038e68757d82c5ea19dcbad3793e382a24a11))
- **adguard**: Update A records for services to point to SVLNAS ([`446f149`](https://github.com/DevSecNinja/truenas-apps/commit/446f149cfce87eb19ee641814d81dfc773ea0ee8))
- **aliases**: Update docker commands for stack management and add ddown alias ([`810b3a5`](https://github.com/DevSecNinja/truenas-apps/commit/810b3a527dc7bc9b2818cb72079cbe677a3021f8))
- **radarr**: Update VLAN IP variables for Radarr service configuration ([`2e0ca51`](https://github.com/DevSecNinja/truenas-apps/commit/2e0ca518f92319cafdfa1c6566d1d48846dc6b74))
- **radarr**: Add Radarr service to documentation and configuration ([`039fb96`](https://github.com/DevSecNinja/truenas-apps/commit/039fb964a401b4b4f61cbb0d6f9d9f82c7f45cff))
- **adguard**: Add split-horizon configuration for local-domain queries ([`51041e1`](https://github.com/DevSecNinja/truenas-apps/commit/51041e1ceedf4554a03e4d5345e09a8b4e1c138e))
- **adguard**: Update DNS configuration to enhance IPv6 support and streamline fallback DNS entries ([`5ca7c6f`](https://github.com/DevSecNinja/truenas-apps/commit/5ca7c6ff8ae5bd83fa3bb61891c5ecaa6b3bc205))
- **radarr**: Dhcp driver not available for init container ([`48861bb`](https://github.com/DevSecNinja/truenas-apps/commit/48861bb24833a1244f64584c26d490d14506787e))
- **radarr**: Update radarr-init container to validate VLAN 70 egress and add DDNS_DOMAIN support ([`60c7fa1`](https://github.com/DevSecNinja/truenas-apps/commit/60c7fa12802e6734c14e159c4bd7ad2a3d864a60))
- **dccd**: Update log message to indicate suppressed output for one-shot deployment ([`b19d888`](https://github.com/DevSecNinja/truenas-apps/commit/b19d88804a9f599cafe64843f26f964844860058))
- **dccd**: Suppress output for one-shot container deployment logs ([`01cf7de`](https://github.com/DevSecNinja/truenas-apps/commit/01cf7dec76db6da5429ce8e6fb8f9e4915af4f25))
- **dccd**: Revert back to one-shot bootstrap logic from 89b4ee1 ([`0104d94`](https://github.com/DevSecNinja/truenas-apps/commit/0104d94e44558dfaed77d0d35dc02c9bb9e05f21))
- **dccd**: Enhance ownership check for root-owned files and provide manual fix instructions ([`28ead0b`](https://github.com/DevSecNinja/truenas-apps/commit/28ead0b800ec0be3a156edbc23d13ebb0a806145))
- **radarr**: Add initial Radarr service configuration and environment secrets ([`0d7abf3`](https://github.com/DevSecNinja/truenas-apps/commit/0d7abf305308942032532063789c839287da4cc2))
- **dccd**: Enhance redeploy function to explicitly wait for specified services ([`ae53730`](https://github.com/DevSecNinja/truenas-apps/commit/ae53730843cc6a86c4c5902f18b381a10e732d38))
- **dccd**: Update user instructions and enforce non-root execution for improved security ([`84ba104`](https://github.com/DevSecNinja/truenas-apps/commit/84ba1047cd833b3e0ee99d12ec16835f7b5332fd))
- **aliases**: Remove sudo from ddeploy and dccd aliases for improved usability ([`8256bbb`](https://github.com/DevSecNinja/truenas-apps/commit/8256bbb7a46861e1bdcc2e246158327f9c419404))
- **architecture**: Update dataset layout for downloads and media organization ([`d1485de`](https://github.com/DevSecNinja/truenas-apps/commit/d1485de905becdf4fc475a55c9ab98481646d19e))
- **bootstrap**: Expand downloads directory structure for torrents and usenet ([`ea3433a`](https://github.com/DevSecNinja/truenas-apps/commit/ea3433aa44d123ef6527b15bdedde5575b3ecc6a))
- **aliases**: Add alias to show resource usage of all containers ([`51be1f1`](https://github.com/DevSecNinja/truenas-apps/commit/51be1f17b7aa5b2f99825c1ff8bb4c8d3ffbdac7))
- **unifi**: Add Traefik configuration for guest portal access ([`3acdc26`](https://github.com/DevSecNinja/truenas-apps/commit/3acdc268fe73ff08fa30eed0054e51cecc2ef481))
- **adguard**: Add remote control configuration for unbound ([`361022c`](https://github.com/DevSecNinja/truenas-apps/commit/361022c82542140d1072160a0f2feffb7b46d778))
- **plex**: Add README for Plex service setup and configuration details ([`de7cdd9`](https://github.com/DevSecNinja/truenas-apps/commit/de7cdd90c1352566a35987f48a9e386ac4015411))
- **dccd**: Add new deployment aliases for all apps and graceful updates ([`669f4d3`](https://github.com/DevSecNinja/truenas-apps/commit/669f4d3dc37f85f4c3035e5fa19a2a64ff9f0f90))
- **architecture**: Update dataset structure and permissions for media and downloads ([`d667dd5`](https://github.com/DevSecNinja/truenas-apps/commit/d667dd5e520b1320797fca8a4a6e8a851aec44ed))
- **aliases**: Add shell aliases and helper functions for Docker management ([`f3a62b6`](https://github.com/DevSecNinja/truenas-apps/commit/f3a62b662ecc62b2adb48d36d0a90651649c03ed))
- **gatus**: Add DNS health checks for AdGuard and external resolution validation ([`01a422f`](https://github.com/DevSecNinja/truenas-apps/commit/01a422f7bcd4d1ff37eff2bcbd79868cd2d87669))

### Miscellaneous

- **deps**: Update docker.io/library/alpine docker tag to v3.23 ([`b9af9fb`](https://github.com/DevSecNinja/truenas-apps/commit/b9af9fba987f69ae9092885c0a60023e5a89b4af))
