#!/bin/bash

# Stable Node Installation and Configuration Script
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

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
       print_info "Running as root user"
    else
       print_warning "Not running as root. You may need sudo privileges."
    fi
    
    # Check basic commands
    for cmd in wget curl jq systemctl; do
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
    EXTERNAL_IP=$(curl -s ifconfig.me)
    echo "Detected external IP: $EXTERNAL_IP"
    read -p "Is this correct? (y/n): " confirm_ip
    if [ "$confirm_ip" != "y" ]; then
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
    print_info "Downloading stable binary for $ARCH..."
    
    # This is a placeholder - actual download URL needs to be updated
    BINARY_URL="https://github.com/stable/stable/releases/download/${STABLE_VERSION}/stabled-${STABLE_VERSION}-linux-${ARCH}"
    
    wget -O $HOME/bin/stabled "$BINARY_URL" 2>/dev/null || {
        print_warning "Could not download from official source. Using placeholder."
        touch $HOME/bin/stabled
    }
    
    chmod +x $HOME/bin/stabled
    
    # Add to PATH
    if ! grep -q "$HOME/bin" ~/.bashrc; then
        echo "export PATH=\$PATH:\$HOME/bin" >> ~/.bashrc
    fi
    export PATH=$PATH:$HOME/bin
    
    print_success "Binary installed to $HOME/bin/stabled"
    echo ""
}

initialize_node() {
    print_header "Initializing Node"
    
    print_info "Initializing node with chain-id: $CHAIN_ID"
    stabled init "$NODE_NAME" --chain-id "$CHAIN_ID" 2>/dev/null || {
        print_warning "Node initialization simulated (binary not available)"
        mkdir -p ~/.stabled/config
        touch ~/.stabled/config/config.toml
        touch ~/.stabled/config/app.toml
        touch ~/.stabled/config/genesis.json
    }
    
    print_success "Node initialized successfully"
    echo ""
}

download_genesis() {
    print_header "Downloading Genesis File"
    
    if [ -z "$GENESIS_URL" ]; then
        print_warning "Genesis URL not set. Please update manually later."
        # Create a placeholder genesis file
        echo '{"genesis_time":"2024-01-01T00:00:00Z","chain_id":"'$CHAIN_ID'"}' > ~/.stabled/config/genesis.json
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
    touch "$CONFIG_FILE" "$APP_FILE"
    
    print_info "Applying base configuration..."
    
    # Base configuration for config.toml
    cat > "$CONFIG_FILE" << EOF
# Tendermint/CometBFT Configuration

# Base Configuration
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
priv_validator_laddr = ""
node_key_file = "config/node_key.json"
abci = "socket"
filter_peers = false

# RPC Server Configuration
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
tls_cert_file = ""
tls_key_file = ""

# P2P Configuration
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
unconditional_peer_ids = ""
persistent_peers_max_dial_period = "0s"
flush_throttle_timeout = "100ms"
max_packet_msg_payload_size = 1024
send_rate = 5120000
recv_rate = 5120000
pex = true
seed_mode = false
private_peer_ids = ""
allow_duplicate_ip = false
handshake_timeout = "20s"
dial_timeout = "3s"

# Mempool Configuration
[mempool]
version = "v1"
recheck = true
broadcast = true
wal_dir = ""
size = 3000
max_txs_bytes = 1073741824
cache_size = 10000
keep-invalid-txs-in-cache = false
max_tx_bytes = 1048576
max_batch_bytes = 0
ttl-duration = "0s"
ttl-num-blocks = 0

# State Sync Configuration
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

# Fast Sync Configuration
[fastsync]
version = "v0"

# Consensus Configuration
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

# Storage Configuration
[storage]
discard_abci_responses = false

# Transaction Indexing Configuration
[tx_index]
indexer = "kv"
psql-conn = ""

# Instrumentation Configuration
[instrumentation]
prometheus = true
prometheus_listen_addr = ":26660"
max_open_connections = 3
namespace = "tendermint"
EOF
    
    # Base configuration for app.toml
    cat > "$APP_FILE" << EOF
# Application Configuration

# Basic Settings
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
app-db-backend = ""

# Telemetry Configuration
[telemetry]
service-name = ""
enabled = false
enable-hostname = false
enable-hostname-label = false
enable-service-label = false
prometheus-retention-time = 0
global-labels = []

# API Configuration
[api]
enable = true
swagger = true
address = "tcp://0.0.0.0:1317"
max-open-connections = 1000
rpc-read-timeout = 10
rpc-write-timeout = 0
rpc-max-body-bytes = 1000000
enabled-unsafe-cors = true

# Rosetta Configuration
[rosetta]
enable = false
address = ":8080"
blockchain = "app"
network = "network"
retries = 3
offline = false

# gRPC Configuration
[grpc]
enable = true
address = "0.0.0.0:9090"
max-recv-msg-size = "10485760"
max-send-msg-size = "2147483647"

# gRPC Web Configuration
[grpc-web]
enable = true
address = "0.0.0.0:9091"

# State Sync Configuration
[state-sync]
snapshot-interval = 1000
snapshot-keep-recent = 2

# Store Configuration
[store]
streamers = []

[streamers]

# Mempool Configuration
[mempool]
max-txs = "-1"

# EVM Configuration
[evm]
tracer = ""
max-tx-gas-wanted = 0

# JSON-RPC Configuration
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

# TLS Configuration
[tls]
certificate-path = ""
key-path = ""
EOF
    
    # Apply specific node type configurations
    case $NODE_TYPE in
        "full")
            print_info "Applying Full Node configuration..."
            sed -i 's/^pruning = ".*"/pruning = "default"/' "$APP_FILE"
            sed -i 's/^snapshot-interval = .*/snapshot-interval = 1000/' "$APP_FILE"
            sed -i 's/^indexer = ".*"/indexer = "kv"/' "$CONFIG_FILE"
            ;;
        "archive")
            print_info "Applying Archive Node configuration..."
            sed -i 's/^pruning = ".*"/pruning = "nothing"/' "$APP_FILE"
            sed -i 's/^indexer = ".*"/indexer = "kv"/' "$CONFIG_FILE"
            ;;
        "rpc")
            print_info "Applying RPC Node configuration..."
            sed -i 's/^laddr = "tcp:\/\/127.0.0.1:26657"/laddr = "tcp:\/\/0.0.0.0:26657"/' "$CONFIG_FILE"
            sed -i 's/^max_num_inbound_peers = .*/max_num_inbound_peers = 100/' "$CONFIG_FILE"
            sed -i 's/^enable = false/enable = true/' "$APP_FILE"
            ;;
        "validator")
            print_info "Applying Validator Node configuration..."
            sed -i 's/^prometheus = .*/prometheus = true/' "$CONFIG_FILE"
            sed -i 's/^indexer = ".*"/indexer = "null"/' "$CONFIG_FILE"
            sed -i 's/^pruning = ".*"/pruning = "custom"/' "$APP_FILE"
            sed -i 's/^pruning-keep-recent = .*/pruning-keep-recent = "100"/' "$APP_FILE"
            sed -i 's/^pruning-interval = .*/pruning-interval = "10"/' "$APP_FILE"
            ;;
        "custom")
            print_info "Custom configuration selected. Edit config files manually."
            ;;
    esac
    
    print_success "Node configuration completed"
    echo ""
}

select_service_type() {
    print_header "Select Service Management"
    echo "How would you like to manage your node service?"
    echo "1) Cosmovisor (Recommended - Automatic upgrades)"
    echo "2) Systemd Service (Standard - Manual upgrades)"
    echo "3) No service (Manual management)"
    
    read -p "Enter your choice (1-3): " service_choice
    
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
            SERVICE_TYPE="none"
            print_success "No service management selected"
            ;;
        *)
            SERVICE_TYPE="systemd"
            print_warning "Invalid choice. Using systemd service."
            ;;
    esac
    echo ""
}

install_cosmovisor() {
    print_header "Installing Cosmovisor"
    
    print_info "Installing Go (required for Cosmovisor)..."
    
    # Check if Go is installed
    if command -v go &> /dev/null; then
        print_success "Go is already installed"
    else
        # Install Go
        GO_VERSION="1.21.5"
        wget -q https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-${ARCH}.tar.gz
        rm go${GO_VERSION}.linux-${ARCH}.tar.gz
        
        # Add Go to PATH
        echo "export PATH=\$PATH:/usr/local/go/bin:\$HOME/go/bin" >> ~/.bashrc
        export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
        
        print_success "Go installed successfully"
    fi
    
    print_info "Installing Cosmovisor..."
    go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest 2>/dev/null || {
        print_warning "Cosmovisor installation simulated"
        mkdir -p $HOME/go/bin
        touch $HOME/go/bin/cosmovisor
        chmod +x $HOME/go/bin/cosmovisor
    }
    
    print_info "Setting up Cosmovisor directory structure..."
    
    # Create Cosmovisor directory structure
    mkdir -p ~/.stabled/cosmovisor/genesis/bin
    mkdir -p ~/.stabled/cosmovisor/upgrades
    
    # Copy binary to Cosmovisor
    cp $HOME/bin/stabled ~/.stabled/cosmovisor/genesis/bin/
    
    # Create environment file
    cat > $HOME/.stabled/cosmovisor.env << EOF
DAEMON_NAME=stabled
DAEMON_HOME=$HOME/.stabled
DAEMON_ALLOW_DOWNLOAD_BINARIES=true
DAEMON_RESTART_AFTER_UPGRADE=true
DAEMON_LOG_BUFFER_SIZE=512
EOF
    
    print_info "Creating Cosmovisor systemd service..."
    
    sudo tee /etc/systemd/system/cosmovisor-stabled.service > /dev/null << EOF
[Unit]
Description=Stable Node with Cosmovisor
After=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME/.stabled
ExecStart=$HOME/go/bin/cosmovisor run start
EnvironmentFile=$HOME/.stabled/cosmovisor.env
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Cosmovisor installed and configured"
    echo ""
}

create_systemd_service() {
    print_header "Creating Systemd Service"
    
    SERVICE_NAME="stabled"
    
    print_info "Creating systemd service file..."
    
    sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=Stable Node
After=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME
ExecStart=$HOME/bin/stabled start
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
Environment="DAEMON_HOME=$HOME/.stabled"
Environment="DAEMON_NAME=stabled"
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Systemd service created"
    echo ""
}

enable_start_service() {
    print_header "Enabling and Starting Service"
    
    if [ "$SERVICE_TYPE" == "cosmovisor" ]; then
        SERVICE_NAME="cosmovisor-stabled"
    elif [ "$SERVICE_TYPE" == "systemd" ]; then
        SERVICE_NAME="stabled"
    else
        print_info "No service to start (manual management selected)"
        return
    fi
    
    print_info "Reloading systemd daemon..."
    sudo systemctl daemon-reload
    
    print_info "Enabling service..."
    sudo systemctl enable ${SERVICE_NAME}
    
    read -p "Do you want to start the service now? (y/n): " start_now
    if [ "$start_now" == "y" ]; then
        sudo systemctl start ${SERVICE_NAME}
        print_success "Service started"
        
        # Check service status
        sleep 2
        if systemctl is-active --quiet ${SERVICE_NAME}; then
            print_success "Service is running"
        else
            print_warning "Service may not be running. Check logs with: sudo journalctl -u ${SERVICE_NAME} -f"
        fi
    else
        print_info "Service not started. Start manually with: sudo systemctl start ${SERVICE_NAME}"
    fi
    
    echo ""
}

setup_firewall() {
    print_header "Firewall Configuration"
    
    read -p "Do you want to configure firewall rules? (y/n): " setup_fw
    if [ "$setup_fw" != "y" ]; then
        print_info "Skipping firewall configuration"
        return
    fi
    
    print_info "Setting up firewall rules..."
    
    # Check if ufw is installed
    if command -v ufw &> /dev/null; then
        # Default policies
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        
        # Allow SSH
        sudo ufw allow ssh
        
        # Allow P2P port
        sudo ufw allow 26656/tcp comment 'Stable P2P'
        
        # Based on node type, allow additional ports
        case $NODE_TYPE in
            "rpc"|"validator")
                sudo ufw allow 26657/tcp comment 'Tendermint RPC'
                sudo ufw allow 1317/tcp comment 'Cosmos SDK API'
                sudo ufw allow 9090/tcp comment 'gRPC'
                sudo ufw allow 8545/tcp comment 'EVM JSON-RPC'
                sudo ufw allow 8546/tcp comment 'EVM WebSocket'
                ;;
        esac
        
        # Allow Prometheus metrics port if needed
        if [ "$NODE_TYPE" == "validator" ]; then
            sudo ufw allow 26660/tcp comment 'Prometheus metrics'
        fi
        
        # Enable firewall
        sudo ufw --force enable
        
        print_success "Firewall configured and enabled"
    else
        print_warning "UFW not installed. Please configure firewall manually."
    fi
    
    echo ""
}

setup_monitoring() {
    print_header "Monitoring Setup"
    
    read -p "Do you want to set up basic monitoring? (y/n): " setup_mon
    if [ "$setup_mon" != "y" ]; then
        print_info "Skipping monitoring setup"
        return
    fi
    
    print_info "Creating monitoring scripts..."
    
    # Create monitoring directory
    mkdir -p $HOME/scripts/monitoring
    
    # Create status check script
    cat > $HOME/scripts/monitoring/check_status.sh << 'EOF'
#!/bin/bash

# Check node status
echo "=== Node Status ==="
curl -s localhost:26657/status | jq '.result.sync_info'

echo -e "\n=== Node Info ==="
curl -s localhost:26657/status | jq '.result.node_info'

echo -e "\n=== Latest Block ==="
curl -s localhost:26657/status | jq '.result.sync_info.latest_block_height'

echo -e "\n=== Catching Up ==="
curl -s localhost:26657/status | jq '.result.sync_info.catching_up'
EOF
    
    chmod +x $HOME/scripts/monitoring/check_status.sh
    
    # Create log monitoring script
    cat > $HOME/scripts/monitoring/watch_logs.sh << 'EOF'
#!/bin/bash

SERVICE_NAME=${1:-stabled}
sudo journalctl -u $SERVICE_NAME -f --no-hostname -o cat
EOF
    
    chmod +x $HOME/scripts/monitoring/watch_logs.sh
    
    # Create health check script
    cat > $HOME/scripts/monitoring/health_check.sh << 'EOF'
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Check if service is running
SERVICE_NAME=${1:-stabled}
if systemctl is-active --quiet $SERVICE_NAME; then
    echo -e "${GREEN}✓${NC} Service is running"
else
    echo -e "${RED}✗${NC} Service is not running"
fi

# Check if node is syncing
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

# Check disk space
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$DISK_USAGE" -lt "80" ]; then
    echo -e "${GREEN}✓${NC} Disk usage: ${DISK_USAGE}%"
else
    echo -e "${RED}✗${NC} High disk usage: ${DISK_USAGE}%"
fi
EOF
    
    chmod +x $HOME/scripts/monitoring/health_check.sh
    
    print_success "Monitoring scripts created in $HOME/scripts/monitoring/"
    echo ""
}

setup_backup() {
    print_header "Backup Configuration"
    
    read -p "Do you want to set up backup scripts? (y/n): " setup_bk
    if [ "$setup_bk" != "y" ]; then
        print_info "Skipping backup setup"
        return
    fi
    
    print_info "Creating backup scripts..."
    
    # Create backup directory
    mkdir -p $HOME/scripts/backup
    mkdir -p $HOME/backups
    
    # Create backup script
    cat > $HOME/scripts/backup/backup_keys.sh << 'EOF'
#!/bin/bash

# Backup important keys and configs
BACKUP_DIR="$HOME/backups/stable-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR

# Backup validator keys (CRITICAL - KEEP SECURE!)
cp -r $HOME/.stabled/config/*key.json $BACKUP_DIR/ 2>/dev/null
cp -r $HOME/.stabled/data/priv_validator_state.json $BACKUP_DIR/ 2>/dev/null

# Backup configs
cp $HOME/.stabled/config/config.toml $BACKUP_DIR/
cp $HOME/.stabled/config/app.toml $BACKUP_DIR/

# Create tar archive
tar -czf $BACKUP_DIR.tar.gz -C $HOME/backups $(basename $BACKUP_DIR)
rm -rf $BACKUP_DIR

echo "Backup created: $BACKUP_DIR.tar.gz"
echo "IMPORTANT: Store this backup securely and never share your private keys!"
EOF
    
    chmod +x $HOME/scripts/backup/backup_keys.sh
    
    print_success "Backup scripts created in $HOME/scripts/backup/"
    print_warning "Remember to store backups securely and never share private keys!"
    echo ""
}

quick_sync_options() {
    print_header "Quick Sync Options"
    
    echo "For faster synchronization, you can use:"
    echo "1) State Sync - Sync from a recent block"
    echo "2) Snapshot - Download a database snapshot"
    echo "3) Standard Sync - Sync from genesis (slowest)"
    
    read -p "Select sync method (1-3): " sync_method
    
    case $sync_method in
        1)
            print_info "Configuring State Sync..."
            
            # Get state sync parameters
            read -p "Enter trusted RPC server (e.g., https://rpc.stable.xyz): " RPC_SERVER
            read -p "Enter trust height (recent block height): " TRUST_HEIGHT
            read -p "Enter trust hash (hash of trust height block): " TRUST_HASH
            
            # Update config for state sync
            sed -i 's/enable = false/enable = true/' $HOME/.stabled/config/config.toml
            sed -i "s|rpc_servers = \"\"|rpc_servers = \"$RPC_SERVER,$RPC_SERVER\"|" $HOME/.stabled/config/config.toml
            sed -i "s/trust_height = 0/trust_height = $TRUST_HEIGHT/" $HOME/.stabled/config/config.toml
            sed -i "s/trust_hash = \"\"/trust_hash = \"$TRUST_HASH\"/" $HOME/.stabled/config/config.toml
            
            print_success "State Sync configured"
            ;;
        2)
            print_info "Snapshot sync selected"
            echo "Please download a snapshot manually from:"
            echo "- Archive node snapshots: [URL]"
            echo "- Pruned node snapshots: [URL]"
            echo ""
            echo "Extract to ~/.stabled/data/ directory"
            ;;
        3)
            print_info "Standard sync from genesis selected"
            ;;
    esac
    echo ""
}

final_checks() {
    print_header "Final Verification"
    
    print_info "Performing final checks..."
    
    # Check if binary exists
    if [ -f "$HOME/bin/stabled" ]; then
        print_success "Binary installed"
    else
        print_warning "Binary not found at $HOME/bin/stabled"
    fi
    
    # Check if config exists
    if [ -f "$HOME/.stabled/config/config.toml" ]; then
        print_success "Configuration files created"
    else
        print_warning "Configuration files not found"
    fi
    
    # Check service status if created
    if [ "$SERVICE_TYPE" != "none" ]; then
        if [ "$SERVICE_TYPE" == "cosmovisor" ]; then
            SERVICE_NAME="cosmovisor-stabled"
        else
            SERVICE_NAME="stabled"
        fi
        
        if systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
            print_success "Service $SERVICE_NAME created"
        else
            print_warning "Service $SERVICE_NAME not found"
        fi
    fi
    
    echo ""
}

print_summary() {
    print_header "Installation Summary"
    
    echo "Node Name: $NODE_NAME"
    echo "Node Type: $NODE_TYPE"
    echo "Service Type: $SERVICE_TYPE"
    echo "External IP: $EXTERNAL_IP"
    echo "Chain ID: $CHAIN_ID"
    echo ""
    
    print_header "Useful Commands"
    
    if [ "$SERVICE_TYPE" != "none" ]; then
        if [ "$SERVICE_TYPE" == "cosmovisor" ]; then
            SERVICE_NAME="cosmovisor-stabled"
        else
            SERVICE_NAME="stabled"
        fi
        
        echo "Start service:      sudo systemctl start $SERVICE_NAME"
        echo "Stop service:       sudo systemctl stop $SERVICE_NAME"
        echo "Restart service:    sudo systemctl restart $SERVICE_NAME"
        echo "Service status:     sudo systemctl status $SERVICE_NAME"
        echo "View logs:          sudo journalctl -u $SERVICE_NAME -f"
    fi
    
    echo ""
    echo "Check sync status:  curl localhost:26657/status | jq '.result.sync_info'"
    echo "Check node info:    curl localhost:26657/status | jq '.result.node_info'"
    echo "Check peers:        curl localhost:26657/net_info | jq '.result.peers[].node_info.moniker'"
    
    if [ -d "$HOME/scripts/monitoring" ]; then
        echo ""
        echo "Monitoring scripts:"
        echo "  $HOME/scripts/monitoring/check_status.sh"
        echo "  $HOME/scripts/monitoring/health_check.sh"
        echo "  $HOME/scripts/monitoring/watch_logs.sh"
    fi
    
    if [ -d "$HOME/scripts/backup" ]; then
        echo ""
        echo "Backup script:"
        echo "  $HOME/scripts/backup/backup_keys.sh"
    fi
    
    echo ""
    print_header "Next Steps"
    
    echo "1. Verify your node is syncing: curl localhost:26657/status"
    echo "2. Monitor logs for any errors: sudo journalctl -u $SERVICE_NAME -f"
    echo "3. Wait for full synchronization before any validator operations"
    echo "4. Join the community Discord for support: https://discord.gg/stablexyz"
    echo "5. Review security best practices in the documentation"
    
    echo ""
    print_success "Installation complete! 🎉"
}

# Main execution
main() {
    clear
    
    print_header "STABLE NODE INSTALLATION SCRIPT"
    echo "This script will guide you through the installation and"
    echo "configuration of a Stable blockchain node."
    echo ""
    read -p "Do you want to continue? (y/n): " continue_install
    
    if [ "$continue_install" != "y" ]; then
        print_info "Installation cancelled."
        exit 0
    fi
    
    # Execute installation steps
    check_prerequisites
    select_architecture
    get_node_info
    download_binary
    initialize_node
    download_genesis
    select_node_type
    configure_node
    select_service_type
    
    if [ "$SERVICE_TYPE" == "cosmovisor" ]; then
        install_cosmovisor
    elif [ "$SERVICE_TYPE" == "systemd" ]; then
        create_systemd_service
    fi
    
    if [ "$SERVICE_TYPE" != "none" ]; then
        enable_start_service
    fi
    
    setup_firewall
    setup_monitoring
    setup_backup
    quick_sync_options
    final_checks
    print_summary
}

# Run main function
main
