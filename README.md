# Overview

Docker Compose for Berachain node.

The `./berachaind` script can be used as a quick-start:

`./berachaind install` brings in docker-ce, if you don't have Docker installed already.

`cp default.env .env`

`nano .env` and adjust variables as needed

`./berachaind up`

To update the software, run `./berachaind update` and then `./berachaind up`

If you want the berachain RPC ports exposed, use `rpc-shared.yml` in `COMPOSE_FILE` inside `.env`.

If meant to be used with [central-proxy-docker](https://github.com/CryptoManufaktur-io/central-proxy-docker) for traefik
and Prometheus remote write; use `:ext-network.yml` in `COMPOSE_FILE` inside `.env` in that case.

This is Berachain Docker v1.1.0
