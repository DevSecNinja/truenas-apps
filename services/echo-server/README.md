# Echo Server

Echo Server is an HTTP echo service that reflects request headers, body, and connection details back to the caller. It's used for testing and debugging Traefik routing, middleware chains, and TLS configuration.

## Why

When troubleshooting reverse proxy issues — wrong headers, broken middleware chains, or TLS misconfigurations — you need a service that simply echoes back what it received. Echo Server provides exactly that, with zero configuration. Point Traefik at it and inspect the response to verify your routing rules work as expected.

## Compose File

- [compose.yaml](https://github.com/DevSecNinja/truenas-apps/blob/main/services/echo-server/compose.yaml)

## Access

| URL                          | Description                          |
| ---------------------------- | ------------------------------------ |
| `https://echo.${DOMAINNAME}` | Echo endpoint (Traefik forward-auth) |

## Architecture

- **Image**: [mendhak/http-https-echo](https://github.com/mendhak/docker-http-https-echo)
- **User/Group**: `3104:3104` (`svc-app-echo`)
- **Networks**: `echo-server-frontend` (Traefik-facing)
- **Reverse proxy**: Traefik with `chain-auth@file` middleware
- **Stateless**: No persistent volumes, no init container

## Secrets

Managed via `secret.sops.env` (SOPS-encrypted, decrypted to `.env` at deploy time):

- `DOMAINNAME` — base domain for Traefik routing

## First-Run Setup

1. Create the dataset `vm-pool/apps/services/echo-server` in TrueNAS
2. Create a `svc-app-echo` group (GID 3104) and user (UID 3104) on the TrueNAS host
3. Deploy — visit `https://echo.${DOMAINNAME}` to see the echoed request details

## Upgrade Notes

No special upgrade procedures. Stateless container. Image updates are managed by Renovate.
