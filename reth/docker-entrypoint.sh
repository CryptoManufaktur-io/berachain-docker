#!/bin/bash
set -e

export CHAIN_SPEC="${CHAIN_SPEC}"
# Set network chain ID
if [[ "$CHAIN_SPEC" == "testnet" ]]; then
    export CHAIN="testnet-beacon-80069"
    export CHAIN_ID="80069"
else
    export CHAIN="mainnet-beacon-80094"
    export CHAIN_ID="80094"
fi

export RETH_DATA=/var/lib/reth
export EL_AUTHRPC_PORT=${EL_AUTH_PORT}
export EL_ETH_PORT=${EL_P2P_PORT}
export PROMETHEUS_PORT=${PROMETHEUS_PORT}
export EL_ETHRPC_PORT=${EL_RPC_PORT}
export RETH_GENESIS_PATH=$RETH_DATA/genesis.json
export LOG_DIR=$RETH_DATA/logs
export JWT_PATH=/common/jwt.hex
export SEED_DATA_DIR=/common/seed-data-$CHAIN_SPEC

# Wait until consensus downloads relevant files
export file_path="$SEED_DATA_DIR/done.txt"
echo "Waiting for $file_path to exist..."
while [ ! -e "$file_path" ]; do
  sleep 1  # Wait for 1 second before checking again
done

# Initialize
if [[ ! -f "${RETH_GENESIS_PATH}" ]]; then
    cp "$SEED_DATA_DIR/eth-genesis.json" "$RETH_GENESIS_PATH"
    reth init --datadir "$RETH_DATA" --chain "$RETH_GENESIS_PATH"
    echo
    echo "✓ Reth set up."
else
    echo "Reth already setup"
fi

if [ -f "$SEED_DATA_DIR/el-peers.txt" ]; then
    EL_PEERS=$(grep '^enode://' "$SEED_DATA_DIR/el-peers.txt"| tr '\n' ',' | sed 's/,$//')
fi

if [ -f "$SEED_DATA_DIR/el-bootnodes.txt" ]; then
    EL_BOOTNODES=$(grep '^enode://' "$SEED_DATA_DIR/el-bootnodes.txt"| tr '\n' ',' | sed 's/,$//')
fi

# Determine my IP
if [ -z "$MY_IP" ]; then
    export MY_IP=$(curl -4 -s ifconfig.me/ip)
    export MY_IP="${MY_IP:-127.0.0.1}"
fi

PEERS_OPTION=${EL_PEERS:+--trusted-peers $EL_PEERS}
BOOTNODES_OPTION=${EL_BOOTNODES:+--bootnodes $EL_BOOTNODES}
ARCHIVE_OPTION=$([ "$EL_ARCHIVE_NODE" = true ] && echo "" || echo "--full")
IP_OPTION=${MY_IP:+--nat extip:$MY_IP}

reth node 					\
	--datadir $RETH_DATA			\
	--chain $RETH_GENESIS_PATH		\
	$ARCHIVE_OPTION				\
    $BOOTNODES_OPTION			\
	$PEERS_OPTION				\
	$IP_OPTION				\
	--authrpc.addr 0.0.0.0		\
	--authrpc.port $EL_AUTHRPC_PORT		\
	--authrpc.jwtsecret $JWT_PATH		\
	--port $EL_ETH_PORT			\
	--metrics $PROMETHEUS_PORT		\
	--http					\
	--http.addr 0.0.0.0			\
	--http.port $EL_ETHRPC_PORT		\
	--ws \
	--ws.addr 0.0.0.0 \
	--ws.port $EL_WSRPC_PORT \
	--ws.origins '*' \
	--ipcpath /tmp/reth.ipc.$EL_ETHRPC_PORT \
	--discovery.port $EL_ETH_PORT	\
	--http.corsdomain '*'			\
	--log.file.directory $LOG_DIR		\
	--engine.persistence-threshold 0	\
	--engine.memory-block-buffer-target 0 
