# Home-Lab Operations Runbook

Run commands on the Docker host. Do not put secret values in this repository, this document, shell history, logs, tickets, or backup filenames.

## 1. Pre-Deployment Gate

1. Record the current state before changing anything:

   ```sh
   date -Iseconds
   docker version
   docker info
   docker compose version
   docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
   docker network ls
   docker volume ls
   df -h /docker /download
   ```

2. For every stack, inventory images, bind mounts, named volumes, published ports, networks, health checks, and required variables. Compare paths with the live container before deployment:

   ```sh
   docker inspect STACK_CONTAINER > /tmp/STACK_CONTAINER.inspect.json
   docker compose --env-file stack.env config --images
   docker compose --env-file stack.env config
   ```

3. Validate every compose file from this directory. Required Portainer or Dockhand values must be exported into the current shell first; never add temporary values to `stack.env` or capture rendered config containing secrets.

   ```sh
   failures=0
   for d in */; do
     [ -f "$d/docker-compose.yaml" ] || continue
     (cd "$d" && docker compose --env-file stack.env config >/dev/null) || failures=1
   done
   test "$failures" -eq 0
   ```

4. Treat warnings, unset variables, invalid interpolation, missing paths, and unexpected image tags as deployment blockers. Keep the pre-change inspect output only until verification is complete, then securely remove it because it can contain environment secrets.

## 2. Networks, Ports, and Secrets

Create the shared external networks once, before deploying dependent stacks:

```sh
docker network inspect front-end >/dev/null 2>&1 || docker network create front-end
docker network inspect back-end >/dev/null 2>&1 || docker network create back-end
docker network inspect front-end
docker network inspect back-end
```

Check listeners and Docker port publications before every deployment:

```sh
sudo ss -lntup
docker ps --format '{{.Names}} {{.Ports}}'
```

BIND9 and CoreDNS are mutually exclusive on a host IP because both require TCP and UDP port 53. Deploy exactly one authoritative owner of each host-IP:53 pair. Stop and disable the other stack before switching, confirm port 53 is free, then start the selected DNS stack. Also check Traefik ports 80, 443, and 8443, TeamSpeak ports 9987/udp, 10011/tcp, and 30033/tcp, and every other published compose port.

Maintain a secret inventory in the password manager and Portainer or Dockhand, recording only metadata:

| Stack | Variable/secret name | Portainer/Dockhand stack | Owner | Rotation date | Consumers | Backup required |
| --- | --- | --- | --- | --- | --- | --- |
| Example | `POSTGRES_PASSWORD` | stack name | operator | YYYY-MM-DD | app, database | yes |

Inventory all blank or required entries in each `stack.env`, including database credentials, JWT/session keys, OAuth/OIDC credentials, API tokens, DNS provider credentials, SMTP credentials, VPN keys, and public/base URLs. Do not record values. Confirm each value exists in Portainer or Dockhand, has the minimum required scope, and has a documented rotation procedure before validating or deploying the stack.

## 3. Backup and Restore

Use encrypted, authenticated off-host backups. Restic to an S3-compatible repository, another machine over SFTP, or removable storage is recommended. Keep repository credentials only in the host secret store or a root-readable environment file outside the repository.

```sh
export RESTIC_REPOSITORY='s3:https://backup.example.invalid/home-lab'
export RESTIC_PASSWORD_FILE='/root/.config/restic/password'
export AWS_ACCESS_KEY_ID='FROM_SECRET_STORE'
export AWS_SECRET_ACCESS_KEY='FROM_SECRET_STORE'
restic snapshots
```

Do not back up live database files as the database backup. Produce a consistent logical/native dump first, then send the dump and application files off-host. Use a root-only staging directory and delete it after `restic backup` succeeds.

```sh
sudo install -d -m 0700 /var/backups/home-lab/STAMP
```

Database examples follow. Replace container and database names with inventory results; use credentials already present inside the containers rather than literal passwords.

```sh
# PostgreSQL: custom format, suitable for pg_restore.
docker exec POSTGRES_CONTAINER sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
  > /var/backups/home-lab/STAMP/postgresql.dump

# MariaDB/MySQL: consistent logical dump including routines, events, and triggers.
docker exec MARIADB_CONTAINER sh -c 'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --events --triggers --all-databases' \
  > /var/backups/home-lab/STAMP/mariadb.sql

# MongoDB: archive format. Supply authentication through container environment or a root-only env file.
docker exec MONGODB_CONTAINER mongodump --archive \
  > /var/backups/home-lab/STAMP/mongodb.archive

# InfluxDB 2.x: inject an operator token from the secret store, not the command line.
docker exec -e INFLUX_TOKEN INFLUXDB_CONTAINER influx backup /tmp/influx-backup
docker cp INFLUXDB_CONTAINER:/tmp/influx-backup /var/backups/home-lab/STAMP/influx-backup
docker exec INFLUXDB_CONTAINER rm -rf /tmp/influx-backup
```

For file-based and SQLite applications, stop the application or use its supported online-backup command before copying. A stopped stack is the safest generic procedure:

```sh
docker compose --env-file stack.env stop
sudo tar --xattrs --acls --numeric-owner -C /docker -cpf /var/backups/home-lab/STAMP/app-files.tar APP_DIRECTORY
docker compose --env-file stack.env start
```

For a named volume, stop all writers and archive it without changing ownership:

```sh
docker run --rm -v VOLUME_NAME:/source:ro -v /var/backups/home-lab/STAMP:/backup alpine \
  tar --numeric-owner -C /source -cpf /backup/VOLUME_NAME.tar .
```

Back up the staging directory, verify it, apply retention, and remove local staging data:

```sh
restic backup /var/backups/home-lab/STAMP
restic check
restic forget --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --keep-yearly 3 --prune
sudo rm -rf /var/backups/home-lab/STAMP
```

Run backups at least daily for mutable data. Keep at least 7 daily, 5 weekly, 12 monthly, and 3 yearly snapshots unless service recovery objectives require more. At least quarterly, restore every backup class into isolated temporary containers/volumes, start the application, authenticate, inspect representative records/files, and record the date, snapshot ID, duration, and result. A backup is not accepted until a restore test passes.

Restore patterns:

```sh
restic restore SNAPSHOT_ID --target /var/restore/home-lab
docker exec -i POSTGRES_CONTAINER pg_restore -U DB_USER -d EMPTY_DATABASE --clean --if-exists < postgresql.dump
docker exec -i MARIADB_CONTAINER sh -c 'mariadb -u root -p"$MYSQL_ROOT_PASSWORD"' < mariadb.sql
docker exec -i MONGODB_CONTAINER mongorestore --archive < mongodb.archive
docker run --rm -v VOLUME_NAME:/target -v /var/restore/home-lab:/restore:ro alpine \
  tar --numeric-owner -C /target -xpf /restore/VOLUME_NAME.tar
```

Restore only into an empty database, directory, or volume unless the application's documented procedure explicitly supports an in-place restore.

## 4. Mandatory Data Migrations

Complete and verify these migrations before the affected stack is recreated. Take a tested off-host backup first.

### Mattermost Paths

The compose target is `/docker/mattermost/postgres` plus `/docker/mattermost/server/{config,data,logs,plugin,client,bleve}`. Compare live mounts with `docker inspect`. If data is in old paths, stop Mattermost and PostgreSQL, create target directories, copy with ownership and metadata preserved, and retain the source until validation:

```sh
sudo install -d /docker/mattermost/server/{config,data,logs,plugin,client,bleve}
sudo rsync -aHAX --numeric-ids /OLD_PATH/ /docker/mattermost/server/TARGET/
```

Do not deploy with empty new directories hiding old data. Verify configuration, attachments, plugins, search, and PostgreSQL row counts after startup.

### TeamSpeak Database

The database target is MariaDB 11.4 at `/docker/teamspeak/mariadb`; the application must connect as `SQL_USER`, not root. Dump the existing database, determine the image's `mysql` UID/GID, prepare the target, and restore into a clean MariaDB 11.4 instance:

```sh
docker run --rm mariadb:11.4 id mysql
sudo install -d /docker/teamspeak/mariadb
sudo chown -R MYSQL_UID:MYSQL_GID /docker/teamspeak/mariadb
```

Set `SQL_DB_NAME`, `SQL_USER`, `SQL_PASS`, and `SQL_ROOT_PASS` in Portainer or Dockhand. Grant `SQL_USER` only the TeamSpeak database, restore the dump, and verify channels, users, permissions, and file transfers. Never point MariaDB 11.4 directly at an unverified data directory created by an incompatible major version.

### Spliit PostgreSQL Version

`POSTGRES_VERSION` is deliberately required and blank. Determine the exact currently deployed PostgreSQL version before deployment; do not guess from a floating image tag:

```sh
docker inspect spliit-db --format '{{.Config.Image}}'
docker exec spliit-db postgres --version
docker exec spliit-db psql -U postgres -Atc 'show server_version;'
```

Set `POSTGRES_VERSION` in Portainer or Dockhand to the exact tested image major/minor expected by the compose expression, and record the full image digest in the change record. If the target major differs, use `pg_dump`/`pg_restore` into a new empty data directory; never start a new PostgreSQL major against `/docker/spliit/data` in place.

### Vikunja PostgreSQL 18 Layout

The compose target is `postgres:18` with `/docker/vikunja/db` mounted at `/var/lib/postgresql`. PostgreSQL 18 uses a versioned data directory below that parent. Before deployment, inspect the running server version and mount destination. If the existing deployment is pre-18 or mounted at `/var/lib/postgresql/data`, dump it and restore into a new empty PostgreSQL 18 parent-mounted directory. Do not move raw cluster files across majors and do not mount an old `data` directory at the PostgreSQL 18 parent. Verify tasks, attachments, users, migrations, mail, and OIDC after restore. Pin the tested Vikunja application tag as part of the same change rather than deploying unreviewed `latest`.

### SearXNG Valkey Ownership

The Valkey target is `/docker/searxng/valkey:/data`. Stop the stack, determine the runtime UID/GID from the exact `valkey:8-alpine` image, then correct the host directory without hard-coding an assumed ID:

```sh
docker run --rm --entrypoint sh docker.io/valkey/valkey:8-alpine -c 'id'
sudo install -d /docker/searxng/valkey
sudo chown -R VALKEY_UID:VALKEY_GID /docker/searxng/valkey
```

Start Valkey first and require a successful `valkey-cli ping` plus persistence-write test before starting SearXNG.

## 5. Host-Managed Traefik and CrowdSec

Traefik configuration remains host-managed. Do not add a repository-local Traefik static or dynamic configuration file.

`/docker/traefik/traefik.yaml` must define:

- Entrypoints `web` on `:80`, `websecure` on `:443`, and `websecurepublic` on `:8443`.
- The Docker provider with `exposedByDefault: false`; current operation uses `unix:///var/run/docker.sock` and Traefik must share `front-end` with routed containers.
- The file provider watching `/docker/traefik/conf`.
- Production and staging ACME resolvers using Cloudflare DNS challenge, persistent root-only `acme.json`, and valid notification email.
- Access logs written under `/docker/traefik/logs` in the format/path consumed by CrowdSec, plus useful application logs.
- API/dashboard disabled or securely routed and authenticated; never use an internet-accessible insecure dashboard.

`/docker/traefik/conf/config.yaml` must define the CrowdSec bouncer middleware named `crowdsec-bouncer` and its plugin/API endpoint and secret supplied outside this repository. The `websecurepublic` entrypoint must apply `crowdsec-bouncer@file` globally, or every public router must explicitly apply it. Fail closed according to the selected bouncer policy.

Validate after every host-side change:

```sh
docker logs traefik --since 10m
docker logs crowdsec --since 10m
docker exec crowdsec cscli metrics
docker exec crowdsec cscli decisions list
curl -fsS http://TRAEFIK_INTERNAL_API/api/entrypoints
curl -fsS http://TRAEFIK_INTERNAL_API/api/http/routers
curl -fsS http://TRAEFIK_INTERNAL_API/api/http/middlewares
```

The API endpoint must be reachable only from an administrative network or container. Confirm all three entrypoints, expected routers/services, valid certificates, and the loaded `crowdsec-bouncer@file` middleware. Generate a controlled denied request or temporary test decision and confirm it is blocked and logged.

Future socket-proxy migration: deploy a read-only Docker socket proxy on an internal network, expose only the minimum Traefik API sections, and change the Docker provider endpoint from `unix:///var/run/docker.sock` to `tcp://docker-socket-proxy:2375`; then remove the socket mount. The current endpoint remains the direct Docker socket until that migration is separately tested.

## 6. BIND9 Installation

Install the reviewed BIND configuration at `/docker/bind9/config/named.conf` before starting the stack. Ensure referenced zone/include files also exist under the mounted config tree and are readable by the container. Validate both configuration and zones with the exact deployed image, for example:

```sh
docker run --rm -v /docker/bind9/config:/etc/bind:ro BIND_IMAGE named-checkconf /etc/bind/named.conf
docker run --rm -v /docker/bind9/config:/etc/bind:ro BIND_IMAGE named-checkzone ZONE_NAME /etc/bind/ZONE_FILE
```

Review `allow-query`, `allow-recursion`, `allow-transfer`, `listen-on`, `listen-on-v6`, and trusted ACLs against current LAN, VLAN, VPN, and Docker subnets. Permit recursion only to intended trusted clients, disable open transfers, and do not use stale broad private-network ACLs. Confirm BIND9/CoreDNS mutual exclusion before startup.

## 7. Public Router Review

After the `websecurepublic` correction, enumerate every router using that entrypoint from the Traefik API and compare it with an approved exposure list. For each router verify the public hostname, DNS record, TLS resolver, backend port, explicit service binding, authentication where required, and CrowdSec middleware inheritance. Remove public labels from services that need only local `web`/`websecure` access. Probe each approved public hostname from outside the LAN; also prove unapproved hostnames and the dashboard are unreachable.

## 8. Runtime Baseline and Limits

Configure Docker daemon log rotation in `/etc/docker/daemon.json` during a maintenance window, merging with existing settings rather than replacing them:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

Validate JSON, restart Docker, and confirm new containers inherit the settings with `docker inspect`. Existing containers must be recreated to inherit daemon logging defaults.

Before setting `mem_limit`, `cpus`, or `pids_limit`, collect at least one normal week including backup, indexing, transcoding, and update peaks:

```sh
docker stats --no-stream
docker inspect CONTAINER --format 'pids={{.HostConfig.PidsLimit}} mem={{.HostConfig.Memory}} nano_cpus={{.HostConfig.NanoCpus}}'
```

Set limits incrementally with headroom and monitor OOM kills, throttling, restart counts, latency, and health checks. Test graceful shutdown for each stateful stack with `docker compose stop`, confirm clean database logs and expected stop time, and set `stop_grace_period` where the default is insufficient. Never validate shutdown with `docker kill`.

## 9. Image Update Policy

- DIUN reports available updates; it does not authorize deployment.
- Watchtower must remain monitor-only with no automatic container updates.
- Resolve floating tags to an exact tested version tag and preferably an immutable digest in the change record. Test backup and restore before production rollout.
- Review release notes, schema migrations, breaking changes, and rollback compatibility. Update one stack at a time.
- Never skip a database major. Follow the vendor-supported major-by-major path or perform a logical dump/restore into a new empty cluster. Keep the old cluster read-only until validation and never downgrade data files.
- Pin database images to an exact tested major/minor or digest. Do not use `latest` for a database.

## 10. Deployment and Verification

Deploy in this order, waiting for health at each step:

1. Host prerequisites: storage, time sync, Docker, firewall, log rotation, external networks, and selected DNS listener.
2. BIND9 or CoreDNS, never both on the same host IP.
3. Docker socket access, Traefik host configuration, CrowdSec, and bouncer.
4. Shared databases, caches, and authentication services.
5. VPN/Gluetun and its dependent arr services.
6. Remaining internal applications.
7. Approved public routers last.

For each stack:

```sh
docker compose --env-file stack.env config >/dev/null
docker compose --env-file stack.env pull
docker compose --env-file stack.env up -d
docker compose --env-file stack.env ps
docker compose --env-file stack.env logs --since 10m
```

Required probes:

- Health: every declared health check is healthy; no restart loops, OOM kills, permission errors, migration failures, or database recovery errors.
- Traefik: local HTTP redirects as intended, HTTPS returns the expected service and certificate, API shows no router/service errors, and public routes use `websecurepublic` plus CrowdSec.
- CrowdSec: acquisition and parser metrics increase, decisions are visible, and a controlled decision is enforced by Traefik.
- VPN: Gluetun is healthy, its public IP matches the VPN, kill-switch behavior is tested, and dependent services have no direct egress when Gluetun stops.
- DNS: query TCP and UDP explicitly from each trusted subnet, test recursive and authoritative answers as applicable, and confirm recursion/transfer is denied from an untrusted client.

Example probes:

```sh
curl -fsSI https://SERVICE.LOCAL_DOMAIN/
curl -fsSI --resolve PUBLIC_NAME:8443:PUBLIC_IP https://PUBLIC_NAME:8443/
dig @DNS_IP NAME A
dig +tcp @DNS_IP NAME A
docker exec gluetun wget -qO- https://api.ipify.org
```

## 11. Rollback

1. Stop the failed stack and prevent repeated migrations or writes.
2. Capture logs, rendered image references, health output, and the failure time without publishing secrets.
3. Revert compose/environment metadata to the last tested version in Portainer or Dockhand and pin the prior immutable image digest.
4. If no persistent-data migration occurred, recreate the prior containers and run all probes.
5. If data changed, do not start old binaries against new-format data. Preserve the failed data directory, create an empty target, restore the pre-change off-host snapshot/dump, then start the prior version.
6. For host Traefik, DNS, or Docker changes, restore the separately backed-up host configuration, validate it offline where possible, restart only the affected service, and rerun routing/security/DNS probes.
7. Keep the pre-change data until application checks and the next backup complete. Record cause, rollback duration, data-loss window, and follow-up action.
