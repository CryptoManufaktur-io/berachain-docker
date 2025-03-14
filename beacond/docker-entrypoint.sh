#!/bin/bash
set -e

# Ensure Beacond binary exists
command -v beacond >/dev/null 2>&1 || { echo >&2 "Error: Beacond binary not found!"; exit 1; }

export CHAIN_SPEC="${CHAIN_SPEC}"
# Set network chain ID
if [[ "$CHAIN_SPEC" == "testnet" ]]; then
    export CHAIN="testnet-beacon-80069"
    export CHAIN_ID="80069"
else
    export CHAIN="mainnet-beacon-80094"
    export CHAIN_ID="80094"
fi

export MONIKER_NAME="${MONIKER_NAME}"
export WALLET_ADDRESS_FEE_RECIPIENT="${WALLET_ADDRESS_FEE_RECIPIENT}"
export EL_ARCHIVE_NODE="${EL_ARCHIVE_NODE}"

# Determine my IP
if [ -z "$MY_IP" ]; then
    export MY_IP=$(curl -4 -s ifconfig.me/ip)
    export MY_IP="${MY_IP:-127.0.0.1}"
fi

# Define directories
export LOG_DIR=$(pwd)/logs
export BEACOND_DATA=$(pwd)
export BEACOND_CONFIG=$BEACOND_DATA/config
export JWT_PATH=/common/jwt.hex

# Define ports (override via env vars)
export CL_RPC_PORT="${CL_RPC_PORT}"
export CL_P2P_PORT="${CL_P2P_PORT}"
export CL_PROXY_PORT="${CL_PROXY_PORT}"

export EL_AUTHRPC_PORT="${EL_AUTH_PORT}"

export PROMETHEUS_PORT="${PROMETHEUS_PORT}"

export SEED_DATA_DIR=/common/seed-data-$CHAIN_SPEC

# Fetch Berachain parameters
echo "Fetching Berachain parameters..."
mkdir -p "$SEED_DATA_DIR"
SEED_DATA_URL="https://raw.githubusercontent.com/berachain/beacon-kit/refs/heads/main/testing/networks/$CHAIN_ID"

curl -s -o "$SEED_DATA_DIR/kzg-trusted-setup.json" "$SEED_DATA_URL/kzg-trusted-setup.json"
curl -s -o "$SEED_DATA_DIR/genesis.json" "$SEED_DATA_URL/genesis.json"
curl -s -o "$SEED_DATA_DIR/eth-genesis.json" $SEED_DATA_URL/eth-genesis.json
curl -s -o "$SEED_DATA_DIR/eth-nether-genesis.json" "$SEED_DATA_URL/eth-nether-genesis.json"
curl -s -o "$SEED_DATA_DIR/el-peers.txt" "$SEED_DATA_URL/el-peers.txt"
curl -s -o "$SEED_DATA_DIR/el-bootnodes.txt" "$SEED_DATA_URL/el-bootnodes.txt"
curl -s -o "$SEED_DATA_DIR/app.toml" "$SEED_DATA_URL/app.toml"
curl -s -o "$SEED_DATA_DIR/config.toml" "$SEED_DATA_URL/config.toml"

# Marker to be used by reth
echo "Done downloading configs" > "$SEED_DATA_DIR/done.txt"

# Initialize Beacond if not already initialized
if [ ! -f "$BEACOND_CONFIG/priv_validator_key.json" ]; then
    echo "Initializing..."
    mkdir -p "$BEACOND_DATA" "$BEACOND_CONFIG" "$LOG_DIR"

    beacond init "$MONIKER_NAME" --chain-id "$CHAIN" --home "$BEACOND_DATA"

    # Generate JWT secret
    beacond jwt generate -o "$JWT_PATH"
    echo "✓ JWT secret generated"

    # Copy seed data
    cp "$SEED_DATA_DIR/genesis.json" "$BEACOND_CONFIG/genesis.json"
    cp "$SEED_DATA_DIR/kzg-trusted-setup.json" "$BEACOND_CONFIG/kzg-trusted-setup.json"
    cp "$SEED_DATA_DIR/app.toml" "$BEACOND_CONFIG/app.toml"
    cp "$SEED_DATA_DIR/config.toml" "$BEACOND_CONFIG/config.toml"
fi

# Update config files with runtime values
dasel put -f "$BEACOND_CONFIG/config.toml" -v "$MONIKER_NAME" moniker
dasel put -f "$BEACOND_CONFIG/config.toml" -v "tcp://0.0.0.0:$CL_RPC_PORT" rpc.laddr
dasel put -f "$BEACOND_CONFIG/config.toml" -v "tcp://0.0.0.0:$CL_P2P_PORT" p2p.laddr
dasel put -f "$BEACOND_CONFIG/config.toml" -v "$MY_IP:$CL_P2P_PORT" p2p.external_address
dasel put -f "$BEACOND_CONFIG/config.toml" -v "tcp://0.0.0.0:$CL_PROXY_PORT" proxy_app
dasel put -f "$BEACOND_CONFIG/config.toml" -v ":$PROMETHEUS_PORT" instrumentation.prometheus_listen_addr

dasel put -f "$BEACOND_CONFIG/app.toml" -v "$JWT_PATH" beacon-kit.engine.jwt-secret-path
dasel put -f "$BEACOND_CONFIG/app.toml" -v "$BEACOND_CONFIG/kzg-trusted-setup.json" beacon-kit.kzg.trusted-setup-path
dasel put -f "$BEACOND_CONFIG/app.toml" -v "$WALLET_ADDRESS_FEE_RECIPIENT" beacon-kit.payload-builder.suggested-fee-recipient
dasel put -f "$BEACOND_CONFIG/app.toml" -v "http://$CHAIN_SPEC-execution:$EL_AUTHRPC_PORT" beacon-kit.engine.rpc-dial-url

echo "✓ Config files updated"

# Validate genesis
if [ ! -f "$BEACOND_CONFIG/genesis.json" ]; then
    echo "Error: Missing genesis.json in $BEACOND_CONFIG!"
    exit 1
fi

beacond genesis validator-root $BEACOND_CONFIG/genesis.json 
echo "✓ Beacon-Kit set up. Confirm genesis root is correct."

# Start Beacond
echo "Starting Beacond..."
if [ -n "$CL_EXTRA_FLAGS" ]; then
    exec "$@" $CL_EXTRA_FLAGS
else
    exec "$@"
fi
