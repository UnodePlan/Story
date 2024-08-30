#!/bin/bash

# Ensure the script is run with root privileges
check_root() {
    if [ "$(id -u)" -ne "0" ]; then
        echo "This script requires root privileges. Please switch to the root user using 'sudo -i' and try again."
        exit 1
    fi
}

# Install necessary system dependencies
install_dependencies() {
    apt update && apt upgrade -y
    apt install -y curl wget jq make gcc nano
}

# Install Node.js and npm
install_nodejs_and_npm() {
    if ! command -v node &> /dev/null; then
        echo "Node.js is not installed, installing..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | bash -
        apt-get install -y nodejs
    else
        echo "Node.js is already installed, version: $(node -v)"
    fi

    if ! command -v npm &> /dev/null; then
        echo "npm is not installed, installing..."
        apt-get install -y npm
    else
        echo "npm is already installed, version: $(npm -v)"
    fi
}

# Install PM2
install_pm2() {
    if ! command -v pm2 &> /dev/null; then
        echo "PM2 is not installed, installing..."
        npm install -g pm2
    else
        echo "PM2 is already installed, version: $(pm2 -v)"
    fi
}

# Download and extract files
download_and_extract() {
    local url=$1
    local dest=$2
    local file=$(basename "$url")

    echo "Downloading $file..."
    wget -q "$url" -O "$file" || { echo "Failed to download $file"; exit 1; }
    echo "Extracting $file..."
    tar -xzf "$file" -C "$dest" || { echo "Failed to extract $file"; exit 1; }
    rm "$file"
}

# Install Story node
install_story_node() {
    install_dependencies
    install_nodejs_and_npm
    install_pm2

    echo "Starting Story node installation..."

    # 下载和解压 geth 和 story 客户端
    download_and_extract "https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-amd64-0.9.2-ea9f0d2.tar.gz" "/usr/local/bin"
    download_and_extract "https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.9.11-2a25df1.tar.gz" "/usr/local/bin"

    echo "Default data folders:"
    echo "Story data root: ${STORY_DATA_ROOT:-/var/lib/story}"
    echo "Geth data root: ${GETH_DATA_ROOT:-/var/lib/geth}"

    # 检查 geth 文件是否存在
    if [ ! -f /usr/local/bin/geth ]; then
        echo "Error: /usr/local/bin/geth not found. Please check the download and extraction process."
        exit 1
    fi

    # 启动执行客户端
    pm2 start /usr/local/bin/geth --name story-geth -- --iliad --syncmode full || { echo "Failed to start story-geth"; exit 1; }

    # 初始化并运行共识客户端
    /usr/local/bin/story init --network iliad || { echo "Failed to initialize story"; exit 1; }
    pm2 start /usr/local/bin/story --name story-client -- run || { echo "Failed to start story-client"; exit 1; }

    echo "Story node installation completed!"
}




# Clear and reinitialize the node
clear_state() {
    echo "Clearing state and reinitializing the node..."
    rm -rf "${GETH_DATA_ROOT:-/var/lib/geth}" && pm2 restart story-geth
    rm -rf "${STORY_DATA_ROOT:-/var/lib/story}" && /usr/local/bin/story init --network iliad && pm2 restart story-client
}

# Check the status of the node
check_status() {
    echo "Checking Geth and Story node status..."
    pm2 logs story-geth
    pm2 logs story-client
}

# Check and load .env file
load_env_file() {
    if [ -f ".env" ]; then
        source .env
        echo "Loaded .env file."
    else
        read -p "Please enter your ETH wallet private key (without '0x' prefix): " PRIVATE_KEY
        echo -e "# ~/story/.env\nPRIVATE_KEY=${PRIVATE_KEY}" > .env
        echo ".env file has been created."
    fi
}

# Validator operations
create_validator() {
    read -p "Enter stake amount (in IP): " STAKE_AMOUNT_IP
    if ! [[ "$STAKE_AMOUNT_IP" =~ ^[0-9]+$ ]]; then
        echo "Invalid amount. Please enter a numeric value."
        return
    fi
    STAKE_AMOUNT_WEI=$((STAKE_AMOUNT_IP * 10**18))
    /usr/local/bin/story validator create --stake ${STAKE_AMOUNT_WEI}
}

stake_to_validator() {
    read -p "Enter validator public key (Base64 format): " VALIDATOR_PUBKEY_BASE64
    read -p "Enter stake amount (in IP): " STAKE_AMOUNT_IP
    if ! [[ "$STAKE_AMOUNT_IP" =~ ^[0-9]+$ ]]; then
        echo "Invalid amount. Please enter a numeric value."
        return
    fi
    STAKE_AMOUNT_WEI=$((STAKE_AMOUNT_IP * 10**18))
    /usr/local/bin/story validator stake --validator-pubkey ${VALIDATOR_PUBKEY_BASE64} --stake ${STAKE_AMOUNT_WEI}
}

unstake_from_validator() {
    read -p "Enter validator public key (Base64 format): " VALIDATOR_PUBKEY_BASE64
    read -p "Enter unstake amount (in IP): " UNSTAKE_AMOUNT_IP
    if ! [[ "$UNSTAKE_AMOUNT_IP" =~ ^[0-9]+$ ]]; then
        echo "Invalid amount. Please enter a numeric value."
        return
    fi
    UNSTAKE_AMOUNT_WEI=$((UNSTAKE_AMOUNT_IP * 10**18))
    /usr/local/bin/story validator unstake --validator-pubkey ${VALIDATOR_PUBKEY_BASE64} --unstake ${UNSTAKE_AMOUNT_WEI}
}

stake_on_behalf() {
    read -p "Enter delegator public key (Base64 format): " DELEGATOR_PUBKEY_BASE64
    read -p "Enter validator public key (Base64 format): " VALIDATOR_PUBKEY_BASE64
    read -p "Enter stake amount (in IP): " STAKE_AMOUNT_IP
    if ! [[ "$STAKE_AMOUNT_IP" =~ ^[0-9]+$ ]]; then
        echo "Invalid amount. Please enter a numeric value."
        return
    fi
    STAKE_AMOUNT_WEI=$((STAKE_AMOUNT_IP * 10**18))
    /usr/local/bin/story validator stake-on-behalf --delegator-pubkey ${DELEGATOR_PUBKEY_BASE64} --validator-pubkey ${VALIDATOR_PUBKEY_BASE64} --stake ${STAKE_AMOUNT_WEI}
}

unstake_on_behalf() {
    read -p "Enter delegator public key (Base64 format): " DELEGATOR_PUBKEY_BASE64
    read -p "Enter validator public key (Base64 format): " VALIDATOR_PUBKEY_BASE64
    read -p "Enter unstake amount (in IP): " UNSTAKE_AMOUNT_IP
    if ! [[ "$UNSTAKE_AMOUNT_IP" =~ ^[0-9]+$ ]]; then
        echo "Invalid amount. Please enter a numeric value."
        return
    fi
    UNSTAKE_AMOUNT_WEI=$((UNSTAKE_AMOUNT_IP * 10**18))
    /usr/local/bin/story validator unstake-on-behalf --delegator-pubkey ${DELEGATOR_PUBKEY_BASE64} --validator-pubkey ${VALIDATOR_PUBKEY_BASE64} --unstake ${UNSTAKE_AMOUNT_WEI}
}

add_operator() {
    read -p "Enter operator's EVM address: " OPERATOR_ADDRESS
    /usr/local/bin/story validator add-operator --operator ${OPERATOR_ADDRESS}
}

remove_operator() {
    read -p "Enter operator's EVM address: " OPERATOR_ADDRESS
    /usr/local/bin/story validator remove-operator --operator ${OPERATOR_ADDRESS}
}

set_withdrawal_address() {
    read -p "Enter new withdrawal address: " WITHDRAWAL_ADDRESS
    /usr/local/bin/story validator set-withdrawal-address --address ${WITHDRAWAL_ADDRESS}
}

# Setup validator
setup_validator() {
    echo "Setting up validator..."
    load_env_file

    echo "Select validator operation:"
    echo "1. Export validator key"
    echo "2. Create new validator"
    echo "3. Stake to existing validator"
    echo "4. Unstake"
    echo "5. Stake on behalf of others"
    echo "6. Unstake on behalf of others"
    echo "7. Add operator"
    echo "8. Remove operator"
    echo "9. Set withdrawal address"
    read -p "Enter option (1-9): " OPTION

    case $OPTION in
    1) /usr/local/bin/story validator export ;;
    2) create_validator ;;
    3) stake_to_validator ;;
    4) unstake_from_validator ;;
    5) stake_on_behalf ;;
    6) unstake_on_behalf ;;
    7) add_operator ;;
    8) remove_operator ;;
    9) set_withdrawal_address ;;
    *) echo "Invalid option." ;;
    esac
}

# Main menu
main_menu() {
    clear
    echo "======================================================================="
    echo "======================================================================="
    echo "Script and tutorial by Unode"
    echo "X: https://x.com/UnodePlan"
    echo "Telegram group: https://t.me/unode_plan"
    echo "Discord community: https://discord.gg/S2F2YPCP"
    echo "Tutorial collection: https://medium.com/@unodeplan"
    echo "======================================================================="
    echo "======================================================================="
    echo "Please select the operation to perform:"
    echo "1. Install Story node"
    echo "2. Clear state and reinitialize"
    echo "3. Check node status"
    echo "4. Setup validator"
    echo "5. Exit"
    read -p "Enter option (1-5): " OPTION

    case $OPTION in
    1) install_story_node ;;
    2) clear_state ;;
    3) check_status ;;
    4) setup_validator ;;
    5) exit 0 ;;
    *) echo "Invalid option." ;;
    esac
}

# Ensure the script runs with root privileges and display the main menu
check_root
main_menu