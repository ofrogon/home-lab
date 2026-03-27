# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a home-lab infrastructure repository — a collection of self-hosted services deployed via Docker Compose. All services live under `docker/stacks_&_docker_compose/`, each in its own subdirectory with a `docker-compose.yaml` and a `stack.env`.

There are no build steps, tests, or linting commands. Work here consists of editing Docker Compose configurations and their associated environment/config files.

## Architecture

### Networking
Two external Docker networks are used across stacks:
- `front-end` — for services that need Traefik routing or inter-stack communication on the public-facing side
- `back-end` — for internal services (databases, caches) that should not be directly reachable from the front-end

These networks must be created on the host before deploying any stack.

### Reverse Proxy (Traefik)
All external-facing services route through Traefik v3.x. Services expose themselves via Docker labels:
```yaml
- "traefik.enable=true"
- "traefik.docker.network=front-end"
- "traefik.http.routers.<name>-https.rule=Host(`<subdomain>.${BASE_URL:?error}`)"
- "traefik.http.routers.<name>-https.entrypoints=websecure"
- "traefik.http.routers.<name>-https.tls.certresolver=production"
- "traefik.http.services.<name>-svc.loadbalancer.server.port=<port>"
```
TLS certificates use Let's Encrypt via Cloudflare DNS challenge (staging and production resolvers defined in `traefik/conf/traefik.yaml`).

A secondary public entrypoint (`websecurepublic` / port 8443) exists for services that need to be reachable externally, using a separate `PUBLIC_URL`.

### Security Layer (CrowdSec)
CrowdSec reads Traefik logs (`/docker/traefik/logs`) and feeds decisions to a Traefik bouncer middleware (`crowdsec-bouncer@file`). The `websecurepublic` entrypoint has this middleware applied globally.

### VPN (arr-stack)
The media automation stack routes all *arr services (Radarr, Sonarr, Lidarr, Readarr, Prowlarr, Bazarr, qBittorrent, Jackett, Flaresolverr) through a Gluetun VPN container (Mullvad/WireGuard) using `network_mode: "service:gluetun"`. Only Gluetun itself is on the `front-end` network and carries all Traefik labels for the other services in the stack.

### Authentication (Authentik)
Authentik runs with PostgreSQL + Redis on the `back-end` network. The server container bridges both `front-end` and `back-end` networks to be reachable via Traefik.

### Deployment Target
Stacks are managed via **Portainer**. Environment variables in `stack.env` files are placeholders — actual secrets are injected through Portainer's stack environment variable UI. The convention `# Set in Portainer` marks variables that must be configured there.

## Conventions

- **Persistent data** mounts to `/docker/<service-name>/` on the host.
- **Media/downloads** mount from `/download/`.
- **Timezone**: `America/Montreal` across all services.
- **PUID/PGID**: LinuxServer.io images use `$PUID` / `$PGID` from `stack.env`.
- **Update monitoring**: `diun.enable=true` label on every container for DIUN notifications.
- **Image versions**: LinuxServer images generally use `:latest`; critical services (Authentik, PostgreSQL) pin versions.
- Commented-out services within a compose file represent disabled/optional components — keep them rather than deleting.
- **Environment variables**: Use YAML mapping format (`KEY: value`) rather than sequence format (`- KEY=value`) in all `environment` blocks.
