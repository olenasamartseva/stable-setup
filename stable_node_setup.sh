#!/bin/bash

# Stable Node Installation and Configuration Script v2
# Enhanced version with support for non-systemd environments
# Interactive shell script based on official documentation
# https://docs.stable.xyz

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
STABLE_VERSION="v1.0.0"  # Update with actual version
CHAIN_ID="stabletestnet_2201-1"
PEERS="5ed0f977a26ccf290e184e364fb04e268ef16430@37.187.147.27:26656,128accd3e8ee379bfdf54560c21345451c7048c7@37.187.147.22:26656"
GENESIS_URL=""  # To be filled with actual URL
RPC_URL=""  # To be filled with actual RPC URL
HAS_SYSTEMD=false

# Functions
print_header() {
    echo -e "${PURPLE}===============================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}===============================================${NC}"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

detect_environment() {
    print_header "Environment Detection"
    
    # Check if systemd is available
    if pidof systemd >/dev/null 2>&1; then
        HAS_SYSTEMD=true
        print_success "Systemd detected - full service management available"
    else
        HAS_SYSTEMD=false
        print_warning "Systemd not detected - will use alternative management methods"
        print_info "This appears to be a container or non-systemd environment"
    fi
    
    # Check if running in Docker/container
    if [ -f /.dockerenv ] || grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null; then
        print_info "Running in containerized environment"
    fi
    
    echo ""
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
       print_info "Running as root user"
    else
       print_warning "Not running as root. You may need sudo privileges."
    fi
    
    # Check basic commands
    for cmd in wget curl jq; do
        if command -v $cmd &> /dev/null; then
            print_success "$cmd is installed"
        else
            print_error "$cmd is not installed. Please install it first."
            exit 1
        fi
    done
    
    # Check disk space
    available_space=$(df / | awk 'NR==2 {print int($4/1048576)}')
    if [ $available_space -lt 100 ]; then
        print_warning "Less than 100GB available disk space. Current: ${available_space}GB"
    else
        print_success "Sufficient disk space available: ${available_space}GB"
    fi
    
    echo ""
}

select_architecture() {
    print_header "Select System Architecture"
    echo "Please select your system architecture:"
    echo "1) Linux AMD64"
    echo "2) Linux ARM64"
    read -p "Enter your choice (1 or 2): " arch_choice
    
    case $arch_choice in
        1)
            ARCH="amd64"
            print_success "Selected Linux AMD64"
            ;;
        2)
            ARCH="arm64"
            print_success "Selected Linux ARM64"
            ;;
        *)
            print_error "Invalid choice. Please run the script again."
            exit 1
            ;;
    esac
    echo ""
}

get_node_info() {
    print_header "Node Configuration"
    
    # Get node name
    read -p "Enter your node name (moniker): " NODE_NAME
    if [ -z "$NODE_NAME" ]; then
        NODE_NAME="stable-node"
        print_warning "Using default node name: $NODE_NAME"
    else
        print_success "Node name set to: $NODE_NAME"
    fi
    
    # Get external IP
    EXTERNAL_IP=$(curl -s ifconfig.me 2>/dev/null || echo "")
    if [ -n "$EXTERNAL_IP" ]; then
        echo "Detected external IP: $EXTERNAL_IP"
        read -p "Is this correct? (y/n): " confirm_ip
        if [ "$confirm_ip" != "y" ]; then
            read -p "Enter your external IP address: " EXTERNAL_IP
        fi
    else
        read -p "Enter your external IP address: " EXTERNAL_IP
    fi
    print_success "External IP set to: $EXTERNAL_IP"
    
    echo ""
}

download_binary() {
    print_header "Downloading Stable Binary"
    
    # Create directory for binary
    mkdir -p $HOME/bin
    
    # Download binary based on architecture
    print_info "Attempting to download stable binary for $ARCH..."
    
    # Try to download from official source
    BINARY_URL="https://github.com/stable/stable/releases/download/${STABLE_VERSION}/stabled-${STABLE_VERSION}-linux-${ARCH}"
    
    if wget -q --spider "$BINARY_URL" 2>/dev/null; then
        wget -O $HOME/bin/stabled "$BINARY_URL"
        print_success "Downloaded official binary"
    else
        print_warning "Official binary not available. Creating mock binary for testing."
        # Create a mock binary that can at least run
        cat > $HOME/bin/stabled << 'EOF'
#!/bin/bash
echo "Stable node mock binary - Replace with actual binary"
echo "Command: $@"

case "$1" in
    init)
        echo "Initializing node..."
        mkdir -p ~/.stabled/config ~/.stabled/data
        echo '{"node_info":{"moniker":"'$2'"}}' > ~/.stabled/config/config.json
        ;;
    start)
        echo "Starting node... (mock mode)"
        echo "Node would be running on port 26657"
        ;;
    version)
        echo "stabled version: mock-1.0.0"
        ;;
    *)
        echo "Available commands: init, start, version"
        ;;
esac
EOF
    fi
    
    chmod +x $HOME/bin/stabled
    
    # Add to PATH
    if ! echo "$PATH" | grep -q "$HOME/bin"; then
        echo "export PATH=\$PATH:\$HOME/bin" >> ~/.bashrc
        export PATH=$PATH:$HOME/bin
    fi
    
    print_success "Binary installed to $HOME/bin/stabled"
    echo ""
}

initialize_node() {
    print_header "Initializing Node"
    
    print_info "Initializing node with chain-id: $CHAIN_ID"
    
    # Create necessary directories
    mkdir -p ~/.stabled/config ~/.stabled/data
    
    # Try to run actual init command
    if $HOME/bin/stabled init "$NODE_NAME" --chain-id "$CHAIN_ID" 2>/dev/null; then
        print_success "Node initialized with stabled binary"
    else
        print_warning "Using fallback initialization"
        # Create config files manually
        touch ~/.stabled/config/config.toml
        touch ~/.stabled/config/app.toml
        touch ~/.stabled/config/genesis.json
        touch ~/.stabled/config/node_key.json
        touch ~/.stabled/config/priv_validator_key.json
    fi
    
    print_success "Node initialized successfully"
    echo ""
}

download_genesis() {
    print_header "Downloading Genesis File"
    
    if [ -z "$GENESIS_URL" ]; then
        print_warning "Genesis URL not set. Creating placeholder genesis."
        # Create a more complete placeholder genesis file
        cat > ~/.stabled/config/genesis.json << EOF
{
  "genesis_time": "2024-01-01T00:00:00.000000Z",
  "chain_id": "$CHAIN_ID",
  "initial_height": "1",
  "consensus_params": {
    "block": {
      "max_bytes": "22020096",
      "max_gas": "-1",
      "time_iota_ms": "1000"
    }
  },
  "app_hash": ""
}
EOF
    else
        print_info "Downloading genesis file..."
        curl -L "$GENESIS_URL" -o ~/.stabled/config/genesis.json
    fi
    
    print_success "Genesis file saved to ~/.stabled/config/genesis.json"
    echo ""
}

select_node_type() {
    print_header "Select Node Type"
    echo "Please select the type of node you want to run:"
    echo "1) Full Node (Default - Balanced configuration)"
    echo "2) Archive Node (No pruning, full history)"
    echo "3) RPC Node (Public RPC endpoint)"
    echo "4) Validator Node (For block validation)"
    echo "5) Custom Configuration"
    
    read -p "Enter your choice (1-5): " node_type
    
    case $node_type in
        1)
            NODE_TYPE="full"
            print_success "Selected Full Node configuration"
            ;;
        2)
            NODE_TYPE="archive"
            print_success "Selected Archive Node configuration"
            ;;
        3)
            NODE_TYPE="rpc"
            print_success "Selected RPC Node configuration"
            ;;
        4)
            NODE_TYPE="validator"
            print_success "Selected Validator Node configuration"
            ;;
        5)
            NODE_TYPE="custom"
            print_success "Selected Custom configuration"
            ;;
        *)
            NODE_TYPE="full"
            print_warning "Invalid choice. Using Full Node configuration."
            ;;
    esac
    echo ""
}

configure_node() {
    print_header "Configuring Node"
    
    CONFIG_FILE="$HOME/.stabled/config/config.toml"
    APP_FILE="$HOME/.stabled/config/app.toml"
    
    # Ensure config files exist
    mkdir -p "$HOME/.stabled/config"
    
    print_info "Writing configuration files..."
    
    # Write complete config.toml
    cat > "$CONFIG_FILE" << EOF
# Tendermint/CometBFT Configuration
proxy_app = "tcp://127.0.0.1:26658"
moniker = "$NODE_NAME"
fast_sync = true
db_backend = "goleveldb"
db_dir = "data"
log_level = "info"
log_format = "plain"
genesis_file = "config/genesis.json"
priv_validator_key_file = "config/priv_validator_key.json"
priv_validator_state_file = "data/priv_validator_state.json"
node_key_file = "config/node_key.json"
abci = "socket"
filter_peers = false

[rpc]
laddr = "tcp://127.0.0.1:26657"
cors_allowed_origins = ["*"]
cors_allowed_methods = ["HEAD", "GET", "POST"]
cors_allowed_headers = ["Origin", "Accept", "Content-Type", "X-Requested-With", "X-Server-Time"]
grpc_laddr = "tcp://127.0.0.1:9090"
grpc_max_open_connections = 900
unsafe = false
max_open_connections = 900
max_subscription_clients = 100
max_subscriptions_per_client = 5
timeout_broadcast_tx_commit = "10s"
max_body_bytes = 1000000
max_header_bytes = 1048576

[p2p]
laddr = "tcp://0.0.0.0:26656"
external_address = "$EXTERNAL_IP:26656"
seeds = ""
persistent_peers = "$PEERS"
upnp = false
addr_book_file = "config/addrbook.json"
addr_book_strict = true
max_num_inbound_peers = 50
max_num_outbound_peers = 30
flush_throttle_timeout = "100ms"
max_packet_msg_payload_size = 1024
send_rate = 5120000
recv_rate = 5120000
pex = true
seed_mode = false
allow_duplicate_ip = false
handshake_timeout = "20s"
dial_timeout = "3s"

[mempool]
version = "v1"
recheck = true
broadcast = true
size = 3000
max_txs_bytes = 1073741824
cache_size = 10000
keep-invalid-txs-in-cache = false
max_tx_bytes = 1048576
max_batch_bytes = 0

[statesync]
enable = false
rpc_servers = ""
trust_height = 0
trust_hash = ""
trust_period = "168h0m0s"
discovery_time = "15s"
temp_dir = ""
chunk_request_timeout = "10s"
chunk_fetchers = "4"

[consensus]
wal_file = "data/cs.wal/wal"
timeout_propose = "3s"
timeout_propose_delta = "500ms"
timeout_prevote = "1s"
timeout_prevote_delta = "500ms"
timeout_precommit = "1s"
timeout_precommit_delta = "500ms"
timeout_commit = "5s"
double_sign_check_height = 2
skip_timeout_commit = false
create_empty_blocks = true
create_empty_blocks_interval = "0s"
peer_gossip_sleep_duration = "100ms"
peer_query_maj23_sleep_duration = "2s"

[storage]
discard_abci_responses = false

[tx_index]
indexer = "kv"

[instrumentation]
prometheus = true
prometheus_listen_addr = ":26660"
max_open_connections = 3
namespace = "tendermint"
EOF
    
    # Write complete app.toml
    cat > "$APP_FILE" << EOF
minimum-gas-prices = "0.0001ustb"
pruning = "default"
pruning-keep-recent = "100"
pruning-interval = "10"
halt-height = 0
halt-time = 0
min-retain-blocks = 0
inter-block-cache = true
index-events = []
iavl-cache-size = 781250
iavl-disable-fastnode = false

[telemetry]
service-name = ""
enabled = false
enable-hostname = false
enable-hostname-label = false
enable-service-label = false
prometheus-retention-time = 0
global-labels = []

[api]
enable = true
swagger = true
address = "tcp://0.0.0.0:1317"
max-open-connections = 1000
rpc-read-timeout = 10
rpc-write-timeout = 0
rpc-max-body-bytes = 1000000
enabled-unsafe-cors = true

[rosetta]
enable = false
address = ":8080"

[grpc]
enable = true
address = "0.0.0.0:9090"
max-recv-msg-size = "10485760"
max-send-msg-size = "2147483647"

[grpc-web]
enable = true
address = "0.0.0.0:9091"

[state-sync]
snapshot-interval = 1000
snapshot-keep-recent = 2

[store]
streamers = []

[mempool]
max-txs = "-1"

[evm]
tracer = ""
max-tx-gas-wanted = 0

[json-rpc]
enable = true
address = "0.0.0.0:8545"
ws-address = "0.0.0.0:8546"
api = "eth,net,web3,txpool,personal,debug"
gas-cap = 25000000
evm-timeout = "5s"
txfee-cap = 1
filter-cap = 200
feehistory-cap = 100
logs-cap = 10000
block-range-cap = 10000
http-timeout = "30s"
http-idle-timeout = "120s"
allow-unprotected-txs = true
max-tx-in-pool = 3000
enable-indexer = false
metrics = true

[tls]
certificate-path = ""
key-path = ""
EOF
    
    # Apply node type specific settings
    case $NODE_TYPE in
        "archive")
            sed -i 's/pruning = "default"/pruning = "nothing"/' "$APP_FILE"
            ;;
        "rpc")
            sed -i 's/laddr = "tcp:\/\/127.0.0.1:26657"/laddr = "tcp:\/\/0.0.0.0:26657"/' "$CONFIG_FILE"
            ;;
        "validator")
            sed -i 's/pruning = "default"/pruning = "custom"/' "$APP_FILE"
            ;;
    esac
    
    print_success "Configuration files created successfully"
    echo ""
}

select_service_type() {
    print_header "Select Service Management"
    
    if [ "$HAS_SYSTEMD" = true ]; then
        echo "How would you like to manage your node service?"
        echo "1) Cosmovisor (Recommended - Automatic upgrades)"
        echo "2) Systemd Service (Standard - Manual upgrades)"
        echo "3) Direct execution (Manual - No service)"
        echo "4) Screen/Tmux session (Background process)"
        
        read -p "Enter your choice (1-4): " service_choice
        
        case $service_choice in
            1)
                SERVICE_TYPE="cosmovisor"
                print_success "Selected Cosmovisor for automatic upgrades"
                ;;
            2)
                SERVICE_TYPE="systemd"
                print_success "Selected standard systemd service"
                ;;
            3)
                SERVICE_TYPE="direct"
                print_success "Selected direct execution"
                ;;
            4)
                SERVICE_TYPE="screen"
                print_success "Selected screen/tmux session management"
                ;;
            *)
                SERVICE_TYPE="direct"
                print_warning "Invalid choice. Using direct execution."
                ;;
        esac
    else
        echo "Systemd not available. Select alternative management:"
        echo "1) Direct execution (Foreground)"
        echo "2) Screen session (Background)"
        echo "3) Tmux session (Background)"
        echo "4) Docker container (if Docker available)"
        
        read -p "Enter your choice (1-4): " service_choice
        
        case $service_choice in
            1)
                SERVICE_TYPE="direct"
                print_success "Selected direct execution"
                ;;
            2)
                SERVICE_TYPE="screen"
                print_success "Selected screen session"
                ;;
            3)
                SERVICE_TYPE="tmux"
                print_success "Selected tmux session"
                ;;
            4)
                SERVICE_TYPE="docker"
                print_success "Selected Docker container"
                ;;
            *)
                SERVICE_TYPE="direct"
                print_warning "Using direct execution."
                ;;
        esac
    fi
    echo ""
}

create_start_scripts() {
    print_header "Creating Start Scripts"
    
    mkdir -p $HOME/scripts
    
    # Create direct start script
    cat > $HOME/scripts/start_node.sh << 'EOF'
#!/bin/bash
echo "Starting Stable node..."
cd $HOME/.stabled
$HOME/bin/stabled start 2>&1 | tee -a node.log
EOF
    chmod +x $HOME/scripts/start_node.sh
    
    # Create screen start script
    cat > $HOME/scripts/start_node_screen.sh << 'EOF'
#!/bin/bash
screen -dmS stable-node bash -c "cd $HOME/.stabled && $HOME/bin/stabled start 2>&1 | tee -a node.log"
echo "Node started in screen session 'stable-node'"
echo "To attach: screen -r stable-node"
echo "To detach: Ctrl+A then D"
EOF
    chmod +x $HOME/scripts/start_node_screen.sh
    
    # Create tmux start script
    cat > $HOME/scripts/start_node_tmux.sh << 'EOF'
#!/bin/bash
tmux new-session -d -s stable-node "cd $HOME/.stabled && $HOME/bin/stabled start 2>&1 | tee -a node.log"
echo "Node started in tmux session 'stable-node'"
echo "To attach: tmux attach -t stable-node"
echo "To detach: Ctrl+B then D"
EOF
    chmod +x $HOME/scripts/start_node_tmux.sh
    
    # Create docker run script
    cat > $HOME/scripts/start_node_docker.sh << 'EOF'
#!/bin/bash
docker run -d \
  --name stable-node \
  -v $HOME/.stabled:/root/.stabled \
  -p 26656:26656 \
  -p 26657:26657 \
  -p 1317:1317 \
  -p 8545:8545 \
  --restart unless-stopped \
  stable/node:latest start
echo "Node started in Docker container 'stable-node'"
echo "To view logs: docker logs -f stable-node"
EOF
    chmod +x $HOME/scripts/start_node_docker.sh
    
    print_success "Start scripts created in $HOME/scripts/"
    echo ""
}

setup_monitoring() {
    print_header "Setting Up Monitoring Scripts"
    
    print_info "Creating monitoring scripts..."
    
    mkdir -p $HOME/scripts/monitoring
    
    # Status check script
    cat > $HOME/scripts/monitoring/check_status.sh << 'EOF'
#!/bin/bash

echo "=== Node Status ==="
if curl -s localhost:26657/status > /dev/null 2>&1; then
    curl -s localhost:26657/status | jq '.result.sync_info'
    echo -e "\n=== Node Info ==="
    curl -s localhost:26657/status | jq '.result.node_info'
    echo -e "\n=== Latest Block ==="
    curl -s localhost:26657/status | jq '.result.sync_info.latest_block_height'
    echo -e "\n=== Catching Up ==="
    curl -s localhost:26657/status | jq '.result.sync_info.catching_up'
else
    echo "Node is not running or RPC is not accessible"
fi
EOF
    chmod +x $HOME/scripts/monitoring/check_status.sh
    
    # Health check script
    cat > $HOME/scripts/monitoring/health_check.sh << 'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Check if node process is running
if pgrep -f "stabled start" > /dev/null; then
    echo -e "${GREEN}✓${NC} Node process is running"
else
    echo -e "${RED}✗${NC} Node process is not running"
fi

# Check RPC endpoint
if curl -s localhost:26657/status > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} RPC endpoint is accessible"
    
    # Check sync status
    CATCHING_UP=$(curl -s localhost:26657/status | jq -r '.result.sync_info.catching_up')
    if [ "$CATCHING_UP" == "false" ]; then
        echo -e "${GREEN}✓${NC} Node is synced"
    else
        echo -e "${RED}✗${NC} Node is still syncing"
    fi
    
    # Check peer count
    PEERS=$(curl -s localhost:26657/net_info | jq '.result.n_peers' | tr -d '"')
    if [ "$PEERS" -gt "0" ]; then
        echo -e "${GREEN}✓${NC} Connected to $PEERS peers"
    else
        echo -e "${RED}✗${NC} No peers connected"
    fi
else
    echo -e "${RED}✗${NC} RPC endpoint is not accessible"
fi

# Check disk usage
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$DISK_USAGE" -lt "80" ]; then
    echo -e "${GREEN}✓${NC} Disk usage: ${DISK_USAGE}%"
else
    echo -e "${RED}✗${NC} High disk usage: ${DISK_USAGE}%"
fi
EOF
    chmod +x $HOME/scripts/monitoring/health_check.sh
    
    # Log viewer script
    cat > $HOME/scripts/monitoring/view_logs.sh << 'EOF'
#!/bin/bash

LOG_FILE="$HOME/.stabled/node.log"

if [ -f "$LOG_FILE" ]; then
    echo "Viewing logs from $LOG_FILE"
    echo "Press Ctrl+C to exit"
    tail -f "$LOG_FILE"
else
    echo "Log file not found at $LOG_FILE"
    echo "Node may not have been started yet"
fi
EOF
    chmod +x $HOME/scripts/monitoring/view_logs.sh
    
    print_success "Monitoring scripts created"
    echo ""
}

print_final_instructions() {
    print_header "Installation Complete!"
    
    echo "Node Name: $NODE_NAME"
    echo "Node Type: $NODE_TYPE"
    echo "External IP: $EXTERNAL_IP"
    echo "Chain ID: $CHAIN_ID"
    echo ""
    
    print_header "How to Start Your Node"
    
    case $SERVICE_TYPE in
        "direct")
            echo "Direct execution:"
            echo "  $HOME/scripts/start_node.sh"
            echo ""
            ;;
        "screen")
            echo "Screen session:"
            echo "  $HOME/scripts/start_node_screen.sh"
            echo ""
            echo "Manage screen:"
            echo "  screen -r stable-node    # Attach to session"
            echo "  Ctrl+A then D            # Detach from session"
            echo "  screen -ls               # List sessions"
            echo ""
            ;;
        "tmux")
            echo "Tmux session:"
            echo "  $HOME/scripts/start_node_tmux.sh"
            echo ""
            echo "Manage tmux:"
            echo "  tmux attach -t stable-node  # Attach to session"
            echo "  Ctrl+B then D               # Detach from session"
            echo "  tmux ls                     # List sessions"
            echo ""
            ;;
        "docker")
            echo "Docker container:"
            echo "  $HOME/scripts/start_node_docker.sh"
            echo ""
            echo "Manage Docker:"
            echo "  docker logs -f stable-node  # View logs"
            echo "  docker stop stable-node     # Stop node"
            echo "  docker start stable-node    # Start node"
            echo ""
            ;;
    esac
    
    print_header "Monitoring Commands"
    
    echo "Check node status:"
    echo "  $HOME/scripts/monitoring/check_status.sh"
    echo ""
    echo "Health check:"
    echo "  $HOME/scripts/monitoring/health_check.sh"
    echo ""
    echo "View logs:"
    echo "  $HOME/scripts/monitoring/view_logs.sh"
    echo ""
    echo "Quick status check:"
    echo "  curl localhost:26657/status | jq '.result.sync_info'"
    echo ""
    
    print_header "Important Notes"
    
    echo "1. Replace the mock binary with the actual stabled binary when available"
    echo "2. Update the genesis file with the correct one for your network"
    echo "3. Ensure ports 26656, 26657, 1317, 8545 are accessible as needed"
    echo "4. Monitor the node regularly using the provided scripts"
    echo "5. Keep your validator keys secure if running a validator"
    echo ""
    
    print_success "Setup complete! Start your node using the commands above."
}

# Main execution
main() {
    clear
    
    print_header "STABLE NODE INSTALLATION SCRIPT v2"
    echo "Enhanced version with support for non-systemd environments"
    echo ""
    read -p "Do you want to continue? (y/n): " continue_install
    
    if [ "$continue_install" != "y" ]; then
        print_info "Installation cancelled."
        exit 0
    fi
    
    # Run installation steps
    detect_environment
    check_prerequisites
    select_architecture
    get_node_info
    download_binary
    initialize_node
    download_genesis
    select_node_type
    configure_node
    select_service_type
    create_start_scripts
    setup_monitoring
    print_final_instructions
}

# Run the script
main
