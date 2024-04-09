#!/bin/bash

echo -e "\033[0;35m"
echo "MMCPRO";
echo -e "\e[0m"

sleep 2

if [ "$(id -u)" != "0" ]; then
    echo "Please run as root"
    exit 1
fi


function yukle() {

service_name="ogd"

if systemctl is-active --quiet "$service_name.service" ; then
    echo "OG node is already installed."
    return 1
fi

# set variables
if [ ! $MONIKER ]; then
	read -p "Enter node name: " MONIKER
	echo 'export MONIKER='$MONIKER >> $HOME/.bash_profile
else
    echo "Node name is already defined: ${MONIKER}"
fi

echo 'export CHAIN_ID="zgtendermint_9000-1"' >> ~/.bash_profile
echo 'export WALLET_NAME="wallet"' >> ~/.bash_profile
echo 'export RPC_PORT="26657"' >> ~/.bash_profile
source $HOME/.bash_profile

echo '================================================='
echo "node name: $MONIKER"
echo "wallet name: $WALLET_NAME"
echo "chain name: $CHAIN_ID"
echo "port: $RPC_PORT"
echo '================================================='
sleep 2

# Update system and install  tools
sudo apt update && sudo apt upgrade -y
sudo apt install curl git jq build-essential gcc unzip wget lz4 -y
sleep 1

# install go
if ! [ -x "$(command -v go)" ]; then
  ver="1.21.6"
  cd $HOME
  wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"
  rm "go$ver.linux-amd64.tar.gz"
  echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.bash_profile
  source ~/.bash_profile
fi
sleep 1

# install evmosd
git clone https://github.com/0glabs/0g-evmos.git
cd 0g-evmos
git checkout v1.0.0-testnet
make install
echo "Evmos version: $(evmosd version)"
sleep 2

# set evmos variables
cd $HOME
evmosd init $MONIKER --chain-id $CHAIN_ID
evmosd config chain-id $CHAIN_ID
evmosd config node tcp://localhost:$RPC_PORT
evmosd config keyring-backend os 

# download genesis.json
wget https://github.com/0glabs/0g-evmos/releases/download/v1.0.0-testnet/genesis.json -O $HOME/.evmosd/config/genesis.json

# set peers and seeds
PEERS="1248487ea585730cdf5d3c32e0c2a43ad0cda973@peer-zero-gravity-testnet.trusted-point.com:26326"
SEEDS="8c01665f88896bca44e8902a30e4278bed08033f@54.241.167.190:26656,b288e8b37f4b0dbd9a03e8ce926cd9c801aacf27@54.176.175.48:26656,8e20e8e88d504e67c7a3a58c2ea31d965aa2a890@54.193.250.204:26656,e50ac888b35175bfd4f999697bdeb5b7b52bfc06@54.215.187.94:26656"
sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/; s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.evmosd/config/config.toml

# set ports and gas prices
EXTERNAL_IP=$(wget -qO- eth0.me)
PROXY_APP_PORT=26658
P2P_PORT=26656
PPROF_PORT=6060
API_PORT=1317
GRPC_PORT=9090
GRPC_WEB_PORT=9091

sed -i \
    -e "s/\(proxy_app = \"tcp:\/\/\)\([^:]*\):\([0-9]*\).*/\1\2:$PROXY_APP_PORT\"/" \
    -e "s/\(laddr = \"tcp:\/\/\)\([^:]*\):\([0-9]*\).*/\1\2:$RPC_PORT\"/" \
    -e "s/\(pprof_laddr = \"\)\([^:]*\):\([0-9]*\).*/\1localhost:$PPROF_PORT\"/" \
    -e "/\[p2p\]/,/^\[/{s/\(laddr = \"tcp:\/\/\)\([^:]*\):\([0-9]*\).*/\1\2:$P2P_PORT\"/}" \
    -e "/\[p2p\]/,/^\[/{s/\(external_address = \"\)\([^:]*\):\([0-9]*\).*/\1${EXTERNAL_IP}:$P2P_PORT\"/; t; s/\(external_address = \"\).*/\1${EXTERNAL_IP}:$P2P_PORT\"/}" \
    $HOME/.evmosd/config/config.toml

sed -i \
    -e "/\[api\]/,/^\[/{s/\(address = \"tcp:\/\/\)\([^:]*\):\([0-9]*\)\(\".*\)/\1\2:$API_PORT\4/}" \
    -e "/\[grpc\]/,/^\[/{s/\(address = \"\)\([^:]*\):\([0-9]*\)\(\".*\)/\1\2:$GRPC_PORT\4/}" \
    -e "/\[grpc-web\]/,/^\[/{s/\(address = \"\)\([^:]*\):\([0-9]*\)\(\".*\)/\1\2:$GRPC_WEB_PORT\4/}" $HOME/.evmosd/config/app.toml

sed -i "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.00252aevmos\"/" $HOME/.evmosd/config/app.toml

# create service
sudo tee /etc/systemd/system/ogd.service > /dev/null <<EOF
[Unit]
Description=OG Node
After=network.target

[Service]
User=$USER
Type=simple
ExecStart=$(which evmosd) start --home $HOME/.evmosd
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# start service
sudo systemctl daemon-reload
sudo systemctl enable ogd
sudo systemctl restart ogd 

echo '=============== INSTALLATION NODE IS FINISHED ==================='
echo 'To check logs: journalctl -u ogd -f -o cat'
echo "To check sync status (false means completed): evmosd status | jq .Sync_info"
sleep 2
}

# Install Snapshot
function snaple() {
    sudo systemctl stop ogd
    wget https://rpc-zero-gravity-testnet.trusted-point.com/latest_snapshot.tar.lz4
    cp $HOME/.evmosd/data/priv_validator_state.json $HOME/.evmosd/priv_validator_state.json.backup
    evmosd tendermint unsafe-reset-all --home $HOME/.evmosd --keep-addr-book
    lz4 -d -c ./latest_snapshot.tar.lz4 | tar -xf - -C $HOME/.evmosd
    mv $HOME/.evmosd/priv_validator_state.json.backup $HOME/.evmosd/data/priv_validator_state.json
    sudo systemctl restart ogd 
    echo '=============== SNAPSHOT INSTALLATION IS FINISHED ==================='
    echo 'To check logs: journalctl -u ogd -f -o cat'
    echo "To check sync status: evmosd status | jq .Sync_info"
    sleep 2
}

function senkron() {
    echo "Sync status: $(evmosd status | jq .SyncInfo.catching_up)"
    echo -n "Press SPACE to continue"
      while true; do
      read -n1 -r
      [[ $REPLY == ' ' ]] && break
      done
      echo
      echo "Continuing ..."
}

function log_gor() {
    echo "To exit, please press ctrl+c on the keyboard"
    sleep 1
    journalctl -u ogd -f -o cat
}



function cuzdan_ekle() {

service_name="ogd"

if ! systemctl is-active --quiet "$service_name.service" ; then
    echo "Install ogd first"
    return 1
fi

source $HOME/.bash_profile
touch wallet.txt
if grep -Fxq "$WALLET_NAME" wallet.txt
then
    echo "${WALLET_NAME} is already defined"
else
    evmosd keys add $WALLET_NAME
    echo $WALLET_NAME >> wallet.txt
    echo "${WALLET_NAME} is added"
    echo -n "Press SPACE to continue"
      while true; do
      read -n1 -r
      [[ $REPLY == ' ' ]] && break
      done
      echo
      echo "Continuing ..."
fi
}

function cuzdan_gor(){
    source $HOME/.bash_profile
    echo "EVM ADDRESS: 0x$(evmosd debug addr $(evmosd keys show $WALLET_NAME -a) | grep hex | awk '{print $3}')"
    echo "PW_KEY IS.."
    evmosd keys unsafe-export-eth-key $WALLET_NAME
    echo -n "Press SPACE to continue"
      while true; do
      read -n1 -r
      [[ $REPLY == ' ' ]] && break
      done
      echo
      echo "Continuing ..."
}

function validator_kur(){
read -n1 -s -r -p $'\033[0;31mBefore setup Validator, make sure that the sync status is false and that you get tokens from faucet(https://faucet.0g.ai/).\nPress space to continue or press any key to cancel...\033[0m\n' key
if [ "$key" = ' ' ]; then
    temp="$(evmosd status | jq .SyncInfo.catching_up)"
    if ! "$temp"
    then
        evmosd tx staking create-validator \
        --amount=10000000000000000aevmos \
        --pubkey=$(evmosd tendermint show-validator) \
        --moniker=$MONIKER \
        --chain-id=$CHAIN_ID \
        --commission-rate=0.05 \
        --commission-max-rate=0.10 \
        --commission-max-change-rate=0.01 \
        --min-self-delegation=1 \
        --from=$WALLET_NAME \
        --identity="" \
        --website="https://t.me/HerculesNode" \
        --details="HerculesNode community" \
        --gas=500000 --gas-prices=99999aevmos \
        -y
    else
        echo "Sync is not completed"
    fi
else
	clear
 	return 1
fi
    
    echo -e "To delegate your validator: tx staking delegate \$(evmosd keys show $WALLET_NAME --bech val -a)  <AMOUNT> aevmos --from $WALLET_NAME --gas=500000 --gas-prices=99999aevmos -y"
    echo -n "Press SPACE to continue"
      while true; do
      read -n1 -r
      [[ $REPLY == ' ' ]] && break
      done
      echo
      echo "Continuing ..."
  
}


function main_menu() {
    while true; do
        clear
        echo "                            MMMCPRO                             "
        echo "================================================================"
        echo "Telegram : https://t.me/HerculesNode"
        echo "1. Install OG node"
        echo "2. Install snapshot"
        echo "3. Check sync status"
        echo "4. See logs"
        echo "5. Add wallets" 
        echo "6. See addres and pw keys"
        echo "7. Setup validator"
        echo "8. Exit"
        read -p "Please enter options （1-8): " OPTION

        case $OPTION in
        1) yukle ;;
        2) snaple ;;
        3) senkron ;;
        4) log_gor ;;
        5) cuzdan_ekle ;;
        6) cuzdan_gor ;;
        7) validator_kur ;;
        8) break;;
        *) echo "Invalid option, re-enter" ;;
        esac
        read -p "Press enter to return to the menu..."
done
}
main_menu
