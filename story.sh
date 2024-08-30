#!/bin/bash

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Check if the script is run as root
if [ "$(id -u)" -ne "0" ]; then
    echo -e "${RED}This script needs to be run as root.${NC}"
    echo -e "${RED}Please use 'sudo -i' to switch to root and run the script again.${NC}"
    exit 1
fi

# Install necessary dependencies
install_dependencies() {
    apt update -y && apt upgrade -y
    apt install -y curl wget jq make gcc nano
}

# Install Node.js and npm
install_nodejs_and_npm() {
    if command -v node > /dev/null; then
        echo -e "${GREEN}Node.js is already installed. Version: $(node -v)${NC}"
    else
        echo -e "${YELLOW}Node.js not found. Installing...${NC}"
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
    if command -v npm > /dev/null; then
        echo -e "${GREEN}npm is already installed. Version: $(npm -v)${NC}"
    else
        echo -e "${YELLOW}npm not found. Installing...${NC}"
        sudo apt-get install -y npm
    fi
}

# Install PM2
install_pm2() {
    if command -v pm2 > /dev/null; then
        echo -e "${GREEN}PM2 is already installed. Version: $(pm2 -v)${NC}"
    else
        echo -e "${YELLOW}PM2 not found. Installing...${NC}"
        npm install pm2@latest -g
    fi
}

# Download a file and show progress bar
download_file() {
    local url=$1
    local output=$2
    echo -e "${YELLOW}Downloading ${url}...${NC}"
    wget --progress=bar:force -O "$output" "$url" 2>&1 | tee /dev/tty | awk '/^ *[0-9]+%/ {print $2}'
}

# Extract a file and show progress
extract_file() {
    local file=$1
    echo -e "${YELLOW}Extracting ${file}...${NC}"
    tar -xzf "$file"
}

# Install the Story node
install_story_node() {
    install_dependencies
    install_nodejs_and_npm
    install_pm2

    echo -e "${GREEN}Starting Story node installation...${NC}"

    # Download execution and consensus clients
    download_file "https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-amd64-0.9.2-ea9f0d2.tar.gz" "geth-linux-amd64-0.9.2-ea9f0d2.tar.gz"
    download_file "https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.9.11-2a25df1.tar.gz" "story-linux-amd64-0.9.11-2a25df1.tar.gz"

    # Extract downloaded files
    extract_file "geth-linux-amd64-0.9.2-ea9f0d2.tar.gz"
    extract_file "story-linux-amd64-0.9.11-2a25df1.tar.gz"

    echo -e "${GREEN}Default data directories set as:${NC}"
    echo -e "${GREEN}Story data root: ${STORY_DATA_ROOT}${NC}"
    echo -e "${GREEN}Geth data root: ${GETH_DATA_ROOT}${NC}"

    # Setup and run execution client
    echo -e "${YELLOW}Setting up execution client...${NC}"
    [[ "$OSTYPE" == "darwin"* ]] && sudo xattr -rd com.apple.quarantine ./geth
    cp /root/geth-linux-amd64-0.9.2-ea9f0d2/geth /usr/local/bin
    pm2 start /usr/local/bin/geth --name story-geth -- --iliad --syncmode full

    # Setup and run consensus client
    echo -e "${YELLOW}Setting up consensus client...${NC}"
    [[ "$OSTYPE" == "darwin"* ]] && sudo xattr -rd com.apple.quarantine ./story
    cp /root/story-linux-amd64-0.9.11-2a25df1/story /usr/local/bin
    /usr/local/bin/story init --network iliad
    pm2 start /usr/local/bin/story --name story-client -- run

    echo -e "${GREEN}Story node installation completed!${NC}"
}

# Clear state and reinitialize the node
clear_state() {
    echo -e "${YELLOW}Clearing state and reinitializing node...${NC}"
    rm -rf ${GETH_DATA_ROOT} && pm2 start /usr/local/bin/geth --name story-geth -- --iliad --syncmode full
    rm -rf ${STORY_DATA_ROOT} && /usr/local/bin/story init --network iliad && pm2 start /usr/local/bin/story --name story-client -- run
}

# Check node status
check_status() {
    echo -e "${YELLOW}Checking Geth status...${NC}"
    pm2 logs story-geth
    pm2 logs story-client
}

# Check .env file and read private key
check_env_file() {
    if [ -f ".env" ]; then
        source .env
        echo -e "${GREEN}.env file loaded. Private key: ${PRIVATE_KEY}${NC}"
    else
        read -p "Please enter your ETH wallet private key (no 0x prefix): " PRIVATE_KEY
        echo "# ~/story/.env" > .env
        echo "PRIVATE_KEY=${PRIVATE_KEY}" >> .env
        echo -e "${GREEN}.env file created. Content:${NC}"
        cat .env
        echo -e "${YELLOW}Ensure the account has received IP funds (refer to tutorial for fund acquisition).${NC}"
    fi
}

# Setup validator
setup_validator() {
    echo -e "${YELLOW}Setting up validator...${NC}"
    check_env_file

    echo -e "${YELLOW}You can perform the following validator actions:${NC}"
    echo "1. Export validator key"
    echo "2. Create new validator"
    echo "3. Stake to existing validator"
    echo "4. Unstake from validator"
    echo "5. Stake on behalf of others"
    echo "6. Unstake on behalf of others"
    echo "7. Add operator"
    echo "8. Remove operator"
    echo "9. Set withdrawal address"
    read -p "Please enter your choice (1-9): " OPTION

    case $OPTION in
    1) export_validator_key ;;
    2) create_validator ;;
    3) stake_to_validator ;;
    4) unstake_from_validator ;;
    5) stake_on_behalf ;;
    6) unstake_on_behalf ;;
    7) add_operator ;;
    8) remove_operator ;;
    9) set_withdrawal_address ;;
    *) echo -e "${RED}Invalid option.${NC}" ;;
    esac
}

# Export validator key
export_validator_key() {
    echo -e "${YELLOW}Exporting validator key...${NC}"
    /usr/local/bin/story validator export
}

# Create new validator
create_validator() {
    read -p "Please enter stake amount (in IP): " AMOUNT_TO_STAKE_IN_IP
    AMOUNT_TO_STAKE_IN_WEI=$((AMOUNT_TO_STAKE_IN_IP * 1000000000000000000))
    /usr/local/bin/story validator create --stake ${AMOUNT_TO_STAKE_IN_WEI}
}

# Stake to existing validator
stake_to_validator() {
    read -p "Please enter validator public key (Base64 format): " VALIDATOR_PUB_KEY_IN_BASE64
    read -p "Please enter stake amount (in IP): " AMOUNT_TO_STAKE_IN_IP
    AMOUNT_TO_STAKE_IN_WEI=$((AMOUNT_TO_STAKE_IN_IP * 1000000000000000000))
    /usr/local/bin/story validator stake --validator-pubkey ${VALIDATOR_PUB_KEY_IN_BASE64} --stake ${AMOUNT_TO_STAKE_IN_WEI}
}

# Unstake from validator
unstake_from_validator() {
    read -p "Please enter validator public key (Base64 format): " VALIDATOR_PUB_KEY_IN_BASE64
    read -p "Please enter unstake amount (in IP): " AMOUNT_TO_UNSTAKE_IN_IP
    AMOUNT_TO_UNSTAKE_IN_WEI=$((AMOUNT_TO_UNSTAKE_IN_IP * 1000000000000000000))
    /usr/local/bin/story validator unstake --validator-pubkey ${VALIDATOR_PUB_KEY_IN_BASE64} --unstake ${AMOUNT_TO_UNSTAKE_IN_WEI}
}

# Stake on behalf of others
stake_on_behalf() {
    read -p "Please enter delegator public key (Base64 format): " DELEGATOR_PUB_KEY_IN_BASE64
    read -p "Please enter validator public key (Base64 format): " VALIDATOR_PUB_KEY_IN_BASE64
    read -p "Please enter stake amount (in IP): " AMOUNT_TO_STAKE_IN_IP
    AMOUNT_TO_STAKE_IN_WEI=$((AMOUNT_TO_STAKE_IN_IP * 1000000000000000000))
    /usr/local/bin/story validator stake-on-behalf --delegator-pubkey ${DELEGATOR_PUB_KEY_IN_BASE64} --validator-pubkey ${VALIDATOR_PUB_KEY_IN_BASE64} --stake ${AMOUNT_TO_STAKE_IN_WEI}
}

# Unstake on behalf of others
unstake_on_behalf() {
    read -p "Please enter delegator public key (Base64 format): " DELEGATOR_PUB_KEY_IN_BASE64
    read -p "Please enter validator public key (Base64 format): " VALIDATOR_PUB_KEY_IN_BASE64
    read -p "Please enter unstake amount (in IP): " AMOUNT_TO_UNSTAKE_IN_IP
    AMOUNT_TO_UNSTAKE_IN_WEI=$((AMOUNT_TO_UNSTAKE_IN_IP * 1000000000000000000))
    /usr/local/bin/story validator unstake-on-behalf --delegator-pubkey ${DELEGATOR_PUB_KEY_IN_BASE64} --validator-pubkey ${VALIDATOR_PUB_KEY_IN_BASE64} --unstake ${AMOUNT_TO_UNSTAKE_IN_WEI}
}

# Add operator
add_operator() {
    read -p "Please enter operator EVM address: " OPERATOR_EVM_ADDRESS
    /usr/local/bin/story validator add-operator --operator ${OPERATOR_EVM_ADDRESS}
}

# Remove operator
remove_operator() {
    read -p "Please enter operator EVM address: " OPERATOR_EVM_ADDRESS
    /usr/local/bin/story validator remove-operator --operator ${OPERATOR_EVM_ADDRESS}
}

# Set withdrawal address
set_withdrawal_address() {
    read -p "Please enter new withdrawal address: " NEW_WITHDRAWAL_ADDRESS
    /usr/local/bin/story validator set-withdrawal-address --address ${NEW_WITHDRAWAL_ADDRESS}
}

# Main menu
main_menu() {
    clear
    echo -e "${GREEN}Script and tutorial created by Twitter user DaDuGe @y95277777. Free and open-source. Do not trust paid versions.${NC}"
    echo -e "${GREEN}============================Artela Node Installation==============================${NC}"
    echo -e "${GREEN}Node community Telegram group: https://t.me/niuwuriji${NC}"
    echo -e "${GREEN}Node community Telegram channel: https://t.me/niuwuriji${NC}"
    echo -e "${GREEN}Node community Discord: https://discord.gg/GbMV5EcNWF${NC}"
    echo -e "${YELLOW}Please choose an action:${NC}"
    echo "1. Install Story node"
    echo "2. Clear state and reinitialize"
    echo "3. Check node status"
    echo "4. Setup validator"
    echo "5. Exit"
    read -p "Please enter your choice (1-5): " OPTION

    case $OPTION in
    1) install_story_node ;;
    2) clear_state ;;
    3) check_status ;;
    4) setup_validator ;;
    5) exit 0 ;;
    *) echo -e "${RED}Invalid option.${NC}" ;;
    esac
}

# Display the main menu
check_env_file  # Check .env file before showing the main menu
main_menu
