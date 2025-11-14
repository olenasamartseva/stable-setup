#!/usr/bin/env bash
set -euo pipefail

CHAIN_ID="stabletestnet_2201-1"
HOME_DIR="${HOME}/.stabled"
KEYRING="test"

# ------------- UI HELPERS -------------

print_header() {
  echo "====================================================="
  echo "        Stable Testnet Node Manager (devnet)         "
  echo "====================================================="
}

print_node_type_hints() {
  cat <<EOF

Choose node type:

  [1] Full Node (no validator)
      - CPU: 4+ cores (Ryzen 5 / i5)
      - RAM: 8+ GB (16 GB recommended)
      - Disk: 500 GB NVMe / SSD

  [2] Validator Node (local devnet)
      - CPU: 8+ cores (Ryzen 7 / i7)
      - RAM: 16+ GB (32 GB recommended)
      - Disk: 1 TB NVMe recommended
      - Produces blocks & participates in consensus (locally)

  [3] Archive Node (no validator, full history)
      - CPU: 16+ cores (Ryzen 9 / i9)
      - RAM: 32+ GB (64 GB recommended)
      - Disk: 4+ TB NVMe
      - Pruning disabled (stores full blockchain history)

EOF
}

# ------------- INPUT -------------

prompt_moniker() {
  read -rp "Enter moniker (node name) [default: dyptan]: " MONIKER
  if [[ -z "${MONIKER}" ]]; then
    MONIKER="dyptan"
  fi
  echo "Using MONIKER=\"${MONIKER}\""
}

select_node_type() {
  print_node_type_hints
  local choice
  while true; do
    read -rp "Select node type [1/2/3]: " choice
    case "$choice" in
      1)
        NODE_TYPE="full"
        echo "Node type: Full Node (no validator)"
        break
        ;;
      2)
        NODE_TYPE="validator"
        echo "Node type: Validator Node (local devnet)"
        break
        ;;
      3)
        NODE_TYPE="archive"
        echo "Node type: Archive Node (no validator)"
        break
        ;;
      *)
        echo "Invalid option. Please enter 1, 2, or 3."
        ;;
    esac
  done
}

# ------------- CONFIG HELPERS -------------

ensure_clean_home() {
  if [[ -d "${HOME_DIR}" ]]; then
    echo
    echo "⚠ ${HOME_DIR} already exists."
    echo "This script is designed for a fresh install."
    echo "If you really want to re-initialize, delete it manually:"
    echo "  rm -rf ${HOME_DIR}"
    echo "and run this script again."
    echo
    exit 1
  fi
}

init_chain() {
  echo
  echo "➤ Initializing chain..."
  stabled init "${MONIKER}" --chain-id "${CHAIN_ID}"
}

configure_pruning() {
  local APP_TOML="${HOME_DIR}/config/app.toml"

  echo
  case "${NODE_TYPE}" in
    full|validator)
      echo "➤ Setting pruning mode: default (Full Node)"
      sed -i.bak 's/^pruning *=.*/pruning = "default"/' "${APP_TOML}"
      ;;
    archive)
      echo "➤ Setting pruning mode: nothing (Archive Node - full history)"
      sed -i.bak 's/^pruning *=.*/pruning = "nothing"/' "${APP_TOML}" || true
      sed -i.bak 's/^snapshot-interval *=.*/snapshot-interval = 0/' "${APP_TOML}" || true
      ;;
    *)
      echo "Unknown NODE_TYPE=${NODE_TYPE}, skipping pruning config"
      ;;
  esac
}

create_validator() {
  if [[ "${NODE_TYPE}" != "validator" ]]; then
    return
  fi

  echo
  echo "➤ Creating local validator key 'myval' (keyring-backend=${KEYRING})"
  echo "   IMPORTANT: Write down the mnemonic shown below and keep it safe!"
  echo "------------------------------------------------------------------"
  stabled keys add myval --keyring-backend "${KEYRING}"

  local VAL_ADDR
  VAL_ADDR="$(stabled keys show myval -a --keyring-backend "${KEYRING}")"

  echo
  echo "➤ Funding validator address in genesis:"
  echo "   ${VAL_ADDR}"
  stabled add-genesis-account "${VAL_ADDR}" 100000000000000000000astable --keyring-backend "${KEYRING}"

  echo
  echo "➤ Creating validator gentx..."
  stabled gentx myval 10000000000000000000astable \
    --chain-id "${CHAIN_ID}" \
    --keyring-backend "${KEYRING}"

  echo
  echo "➤ Collecting gentxs into genesis..."
  stabled collect-gentxs

  echo
  echo "➤ Final genesis validation..."
  stabled validate-genesis
}

start_node() {
  echo
  echo "➤ Starting node (logs will stream here, Ctrl+C to stop)..."
  echo

  cd "${HOME_DIR}"

  # Build common start command
  cmd=(
    stabled start
    --chain-id "${CHAIN_ID}"
    --json-rpc.enable
    --json-rpc.address 0.0.0.0:8545
    --json-rpc.api eth,net,web3
  )

  echo "Command:"
  echo "  ${cmd[*]}"
  echo

  # Run and stream logs
  "${cmd[@]}" 2>&1 | tee -a "${HOME_DIR}/node.log"
}

# ------------- SECRETS BACKUP -------------

backup_secrets() {
  print_header
  echo "➤ Exporting security-related data (keys, node keys, validator keys)..."
  echo

  if [[ ! -d "${HOME_DIR}" ]]; then
    echo "No ${HOME_DIR} directory found. Nothing to backup."
    exit 1
  fi

  local OUT="stabled_secrets_backup_$(date +%F_%H-%M-%S).txt"

  {
    echo "==================== STABLED SECRETS BACKUP ===================="
    echo "Generated at: $(date -Iseconds)"
    echo "Home dir: ${HOME_DIR}"
    echo

    echo "---- stabled keys (keyring-backend=${KEYRING}) ----"
    stabled keys list --keyring-backend "${KEYRING}" -o json || echo "keys list failed"
    echo

    if [[ -f "${HOME_DIR}/config/node_key.json" ]]; then
      echo "---- node_key.json (P2P node id / private key) ----"
      cat "${HOME_DIR}/config/node_key.json"
      echo
    fi

    if [[ -f "${HOME_DIR}/config/priv_validator_key.json" ]]; then
      echo "---- priv_validator_key.json (validator signing key) ----"
      cat "${HOME_DIR}/config/priv_validator_key.json"
      echo
    fi

    if [[ -f "${HOME_DIR}/config/genesis.json" ]]; then
      echo "---- genesis.json auth.accounts ----"
      jq '.app_state.auth.accounts' "${HOME_DIR}/config/genesis.json" 2>/dev/null || echo "jq failed on genesis"
      echo
    fi

    echo "====================== END OF BACKUP ==========================="
    echo
    echo "NOTE: The mnemonic phrase for 'myval' was ONLY shown once when the"
    echo "'stabled keys add myval' command ran. If you didn't store it then,"
    echo "it cannot be recovered from these files."
  } > "${OUT}"

  echo "✅ Backup file created:"
  echo "   $(pwd)/${OUT}"
  echo
  echo "Store this file in a VERY safe place (offline if possible)."
}

# ------------- MAIN -------------

main() {
  if [[ "${1-}" == "backup" ]]; then
    backup_secrets
    exit 0
  fi

  print_header
  echo "This will perform a FRESH install of a local Stable testnet node."
  echo "Current CHAIN_ID: ${CHAIN_ID}"
  echo

  ensure_clean_home
  prompt_moniker
  select_node_type
  init_chain
  configure_pruning
  create_validator    # only if NODE_TYPE=validator
  echo
  echo "➤ Final genesis validation..."
  stabled validate-genesis
  start_node          # blocks & shows logs
}

main "$@"
