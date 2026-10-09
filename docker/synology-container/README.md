# Synology Container Networks

The Immich and Nextcloud AIO projects use external Docker networks so Synology
Container Manager cannot replace their subnets during a project clean or update.
DSM firewall rules must allow the complete subnet, not individual container IPs.

Before deploying either project, verify that the proposed ranges do not overlap
the LAN, VLANs, VPN routes, virtual-machine networks, or existing Docker networks:

```sh
docker network ls
docker network inspect bridge
ip route
```

Create the persistent networks once through SSH or a DSM Task Scheduler task:

```sh
docker network create \
  --driver bridge \
  --subnet 172.30.10.0/24 \
  --gateway 172.30.10.1 \
  immich-network

docker network create \
  --driver bridge \
  --subnet 172.30.20.0/24 \
  --gateway 172.30.20.1 \
  nextcloud-aio
```

Configure DSM firewall rules for `172.30.10.0/24` and `172.30.20.0/24` as
required by the applications. Do not remove these networks during project
cleanup and do not run `docker network prune` while either network is unused.

The published application ports bind to `192.168.1.5` by default. Override
`NAS_IP` in each local `.env` file if the NAS address is different. Restrict DSM
firewall access as follows:

- Allow TCP `2283` only from the Traefik host to Immich.
- Allow TCP `11000` only from the Traefik host to Nextcloud Apache.
- Allow TCP `9988` only from trusted administration addresses.

If a network already exists with an automatically assigned subnet, stop and
remove all containers attached to it before removing and recreating the network.
For Nextcloud AIO, stop the containers from its management interface, remove the
AIO-created child containers, and verify that no endpoint remains attached:

```sh
docker network inspect nextcloud-aio
```

Only then remove and recreate the `nextcloud-aio` network.

Immich requires a local `.env` file. Copy `immich/stack.env` to `.env`, fill in
the values, and keep the resulting `.env` file out of version control.
Do the same with `nextcloud/stack.env` before deploying Nextcloud AIO.

Nextcloud uses the existing `/volume1/docker/NextCloud` path for both its
configured data directory and the bind-backed AIO configuration volume. Do not
change either path on an initialized instance without an AIO backup and a tested
migration. For a new installation, use separate directories for AIO configuration
and user data from the beginning.
