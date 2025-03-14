#!/bin/bash
set -e

# Ensure Beacond binary exists
command -v beacond >/dev/null 2>&1 || { echo >&2 "Error: Beacond binary not found!"; exit 1; }

# Default environment variables (can be overridden at runtime)
export CHAIN_SPEC="${CHAIN_SPEC:-mainnet}"  # "mainnet" or "testnet"
export MONIKER_NAME="${MONIKER_NAME:-camembera}"
export WALLET_ADDRESS_FEE_RECIPIENT="${WALLET_ADDRESS_FEE_RECIPIENT:-0x9BcaA41DC32627776b1A4D714Eef627E640b3EF5}"
export EL_ARCHIVE_NODE="${EL_ARCHIVE_NODE:-false}"
export MY_IP=$(curl -s ifconfig.me/ip)
export MY_IP="${MY_IP:-127.0.0.1}"  # Default if empty

# Define directories
export LOG_DIR=$(pwd)/logs
export BEACOND_BIN=beacond
export BEACOND_DATA="$DAEMON_HOME"
export BEACOND_CONFIG=$BEACOND_DATA/config
export JWT_PATH=$BEACOND_CONFIG/jwt.hex

# Define ports (override via env vars)
export CL_ETHRPC_PORT="${CL_ETHRPC_PORT:-26657}"
export CL_ETHP2P_PORT="${CL_ETHP2P_PORT:-26656}"
export CL_ETHPROXY_PORT="${CL_ETHPROXY_PORT:-26658}"
export EL_ETHRPC_PORT="${EL_ETHRPC_PORT:-8545}"
export EL_AUTHRPC_PORT="${EL_AUTHRPC_PORT:-8551}"
export EL_ETH_PORT="${EL_ETH_PORT:-30303}"
export PROMETHEUS_PORT="${PROMETHEUS_PORT:-9101}"

# Set network chain ID
if [[ "$CHAIN_SPEC" == "testnet" ]]; then
    export CHAIN="testnet-beacon-80069"
    export CHAIN_ID="80069"
else
    export CHAIN="mainnet-beacon-80094"
    export CHAIN_ID="80094"
fi

export SEED_DATA_DIR=$(pwd)/seed-data-$CHAIN_ID

# Fetch Berachain parameters
echo "Fetching Berachain parameters..."
mkdir -p "$SEED_DATA_DIR"
SEED_DATA_URL="https://raw.githubusercontent.com/berachain/beacon-kit/refs/heads/main/testing/networks/$CHAIN_ID"

curl -s -o "$SEED_DATA_DIR/kzg-trusted-setup.json" "$SEED_DATA_URL/kzg-trusted-setup.json"
curl -s -o "$SEED_DATA_DIR/genesis.json" "$SEED_DATA_URL/genesis.json"
curl -s -o "$SEED_DATA_DIR/eth-genesis.json" "$SEED_DATA_URL/eth-genesis.json"
curl -s -o "$SEED_DATA_DIR/eth-nether-genesis.json" "$SEED_DATA_URL/eth-nether-genesis.json"
curl -s -o "$SEED_DATA_DIR/el-peers.txt" "$SEED_DATA_URL/el-peers.txt"
curl -s -o "$SEED_DATA_DIR/el-bootnodes.txt" "$SEED_DATA_URL/el-bootnodes.txt"
curl -s -o "$SEED_DATA_DIR/app.toml" "$SEED_DATA_URL/app.toml"
curl -s -o "$SEED_DATA_DIR/config.toml" "$SEED_DATA_URL/config.toml"

# Initialize Beacond if not already initialized
if [ ! -f "$BEACOND_CONFIG/priv_validator_key.json" ]; then
    echo "Initializing..."
    mkdir -p "$BEACOND_DATA" "$BEACOND_CONFIG" "$LOG_DIR"

    $BEACOND_BIN init "$MONIKER_NAME" --chain-id "$CHAIN" --home "$BEACOND_DATA"

    # Generate JWT secret
    $BEACOND_BIN jwt generate -o "$JWT_PATH"
    echo "✓ JWT secret generated"

    # Copy seed data
    cp "$SEED_DATA_DIR/genesis.json" "$BEACOND_CONFIG/genesis.json"
    cp "$SEED_DATA_DIR/kzg-trusted-setup.json" "$BEACOND_CONFIG/kzg-trusted-setup.json"
    cp "$SEED_DATA_DIR/app.toml" "$BEACOND_CONFIG/app.toml"
    cp "$SEED_DATA_DIR/config.toml" "$BEACOND_CONFIG/config.toml"
fi

# Update config files with runtime values
dasel put -f "$BEACOND_CONFIG/config.toml" -v "$MONIKER_NAME" moniker
dasel put -f "$BEACOND_CONFIG/config.toml" -v "tcp://0.0.0.0:$CL_ETHRPC_PORT" rpc.laddr
dasel put -f "$BEACOND_CONFIG/config.toml" -v "tcp://0.0.0.0:$CL_ETHP2P_PORT" p2p.laddr
dasel put -f "$BEACOND_CONFIG/config.toml" -v "$MY_IP:$CL_ETHP2P_PORT" p2p.external_address
dasel put -f "$BEACOND_CONFIG/config.toml" -v "tcp://0.0.0.0:$CL_ETHPROXY_PORT" proxy_app
dasel put -f "$BEACOND_CONFIG/config.toml" -v ":$PROMETHEUS_PORT" instrumentation.prometheus_listen_addr

dasel put -f "$BEACOND_CONFIG/app.toml" -v "$JWT_PATH" beacon-kit.engine.jwt-secret-path
dasel put -f "$BEACOND_CONFIG/app.toml" -v "$BEACOND_CONFIG/kzg-trusted-setup.json" beacon-kit.kzg.trusted-setup-path
dasel put -f "$BEACOND_CONFIG/app.toml" -v "$WALLET_ADDRESS_FEE_RECIPIENT" beacon-kit.payload-builder.suggested-fee-recipient
dasel put -f "$BEACOND_CONFIG/app.toml" -v "http://localhost:$EL_AUTHRPC_PORT" beacon-kit.engine.rpc-dial-url

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
if [ -n "$EXTRA_FLAGS" ]; then
    exec "$@" $EXTRA_FLAGS
else
    exec "$@"
fi
