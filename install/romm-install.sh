#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: DevelopmentCats
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://romm.app
# Updated: 03/10/2025

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing System Dependencies"
$STD apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    mc \
    sudo \
    gnupg2 \
    mariadb-server \
    redis-server \
    python3 \
    python3-pip \
    python3-venv
msg_ok "Installed System Dependencies"

msg_info "Setting up Node.js Repository"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
$STD apt-get install -y nodejs
msg_ok "Set up Node.js Repository"

msg_info "Setting up MariaDB"
systemctl start mariadb
systemctl enable mariadb

# Generate secure passwords
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=')
DB_NAME=romm
DB_USER=romm_user
DB_PASS=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c16)
AUTH_SECRET_KEY=$(openssl rand -hex 32)

# Secure MySQL installation
mysql -e "UPDATE mysql.user SET Password=PASSWORD('$MYSQL_ROOT_PASSWORD') WHERE User='root'"
mysql -e "DELETE FROM mysql.user WHERE User=''"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
mysql -e "DROP DATABASE IF EXISTS test"
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'"
mysql -e "FLUSH PRIVILEGES"

# Create RomM database and user
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS'"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES"

{
    echo "RomM Credentials"
    echo "RomM Database User: $DB_USER"
    echo "RomM Database Password: $DB_PASS"
    echo "RomM Database Name: $DB_NAME"
    echo "MySQL Root Password: $MYSQL_ROOT_PASSWORD"
    echo "RomM Auth Secret Key: $AUTH_SECRET_KEY"
} >> ~/romm.creds
msg_ok "Set up MariaDB"

msg_info "Configuring Redis"
sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf
systemctl restart redis-server
systemctl enable redis-server
msg_ok "Configured Redis"

msg_info "Setting up RomM Directory Structure"
# Create directories with proper folder structure (Structure A - recommended)
mkdir -p /opt/romm
mkdir -p /opt/romm/library/roms/{gbc,gba,ps}
mkdir -p /opt/romm/library/bios/{gba,ps}
mkdir -p /opt/romm/assets/saves
mkdir -p /opt/romm/assets/states
mkdir -p /opt/romm/assets/screenshots
mkdir -p /opt/romm/config
mkdir -p /opt/romm/resources
msg_ok "Created RomM Directory Structure"

msg_info "Cloning RomM Repository"
# Clone the repository
git clone https://github.com/rommapp/romm.git /opt/romm/app
msg_ok "Cloned RomM Repository"

msg_info "Setting up Python Environment"
# Set up Python virtual environment
python3 -m venv /opt/romm/venv
source /opt/romm/venv/bin/activate
pip install --upgrade pip
pip install poetry
msg_ok "Set up Python Environment"

msg_info "Installing Backend Dependencies"
# Install backend dependencies
cd /opt/romm/app
poetry install
msg_ok "Installed Backend Dependencies"

msg_info "Building Frontend"
# Build frontend
cd /opt/romm/app/frontend
npm install
npm run build
msg_ok "Built Frontend"

# Interactive configuration for API keys and background tasks
echo -e "\n${GN}=== RomM Configuration ===${CL}"
echo -e "${YW}You can configure RomM now or leave settings empty to configure later through the web interface.${CL}\n"

# API Keys configuration - now asking about each provider individually
echo -e "${BL}Metadata Provider API Keys${CL}"
echo -e "These keys enhance game metadata and images. You can configure any, all, or none."

# Initialize variables for API keys
IGDB_CLIENT_ID=""
IGDB_CLIENT_SECRET=""
MOBYGAMES_API_KEY=""
STEAMGRIDDB_API_KEY=""

# IGDB/Twitch config
read -p "Configure IGDB/Twitch API keys? (y/n) [n]: " CONFIGURE_IGDB
CONFIGURE_IGDB=${CONFIGURE_IGDB:-n}
if [[ "${CONFIGURE_IGDB,,}" == "y" ]]; then
    echo -e "\n${YW}IGDB/Twitch API Keys${CL}"
    echo -e "Get these from https://api-docs.igdb.com/#account-creation"
    read -p "IGDB Client ID: " IGDB_CLIENT_ID
    read -p "IGDB Client Secret: " IGDB_CLIENT_SECRET
fi

# MobyGames config
read -p "Configure MobyGames API key? (y/n) [n]: " CONFIGURE_MOBYGAMES
CONFIGURE_MOBYGAMES=${CONFIGURE_MOBYGAMES:-n}
if [[ "${CONFIGURE_MOBYGAMES,,}" == "y" ]]; then
    echo -e "\n${YW}MobyGames API Key${CL}"
    echo -e "Get this from https://www.mobygames.com/info/api/"
    read -p "MobyGames API Key: " MOBYGAMES_API_KEY
fi

# SteamGridDB config
read -p "Configure SteamGridDB API key? (y/n) [n]: " CONFIGURE_STEAMGRID
CONFIGURE_STEAMGRID=${CONFIGURE_STEAMGRID:-n}
if [[ "${CONFIGURE_STEAMGRID,,}" == "y" ]]; then
    echo -e "\n${YW}SteamGridDB API Key${CL}"
    echo -e "Get this from https://www.steamgriddb.com/profile/preferences/api"
    read -p "SteamGridDB API Key: " STEAMGRIDDB_API_KEY
fi

# Background tasks configuration
echo -e "\n${BL}Background Tasks Configuration${CL}"

read -p "Enable automatic re-scanning when files change? (y/n) [y]: " ENABLE_RESCAN_CHANGE
ENABLE_RESCAN_CHANGE=${ENABLE_RESCAN_CHANGE:-y}
ENABLE_RESCAN_ON_FILESYSTEM_CHANGE="false"
if [[ "${ENABLE_RESCAN_CHANGE,,}" == "y" ]]; then
    ENABLE_RESCAN_ON_FILESYSTEM_CHANGE="true"
    read -p "Delay in minutes before re-scanning (default: 5): " RESCAN_DELAY
    RESCAN_DELAY=${RESCAN_DELAY:-5}
fi

read -p "Enable scheduled daily re-scanning? (y/n) [y]: " ENABLE_SCHEDULED
ENABLE_SCHEDULED=${ENABLE_SCHEDULED:-y}
ENABLE_SCHEDULED_RESCAN="false"
if [[ "${ENABLE_SCHEDULED,,}" == "y" ]]; then
    ENABLE_SCHEDULED_RESCAN="true"
    read -p "Cron expression for scheduled re-scanning (default: '0 3 * * *' - 3 AM daily): " SCHEDULED_CRON
    SCHEDULED_CRON=${SCHEDULED_CRON:-"0 3 * * *"}
fi

read -p "Enable scheduled Switch TitleDB updates? (y/n) [n]: " ENABLE_SWITCH_UPDATE
ENABLE_SWITCH_UPDATE=${ENABLE_SWITCH_UPDATE:-n}
ENABLE_SCHEDULED_UPDATE_SWITCH_TITLEDB="false"
if [[ "${ENABLE_SWITCH_UPDATE,,}" == "y" ]]; then
    ENABLE_SCHEDULED_UPDATE_SWITCH_TITLEDB="true"
    read -p "Cron expression for Switch TitleDB updates (default: '0 4 * * *' - 4 AM daily): " SWITCH_UPDATE_CRON
    SWITCH_UPDATE_CRON=${SWITCH_UPDATE_CRON:-"0 4 * * *"}
fi

msg_info "Configuring RomM Environment"
# Create environment configuration with all required variables
cat <<EOF >/opt/romm/config/.env
# Application settings
PORT=8080
HOST=0.0.0.0
LOG_LEVEL=info
DEVELOPMENT_MODE=false

# Dependencies
DB_HOST=localhost
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWD=$DB_PASS
REDIS_HOST=localhost
REDIS_PORT=6379

# Authentication
ROMM_AUTH_SECRET_KEY=$AUTH_SECRET_KEY

# Metadata providers
IGDB_CLIENT_ID=$IGDB_CLIENT_ID
IGDB_CLIENT_SECRET=$IGDB_CLIENT_SECRET
MOBYGAMES_API_KEY=$MOBYGAMES_API_KEY
STEAMGRIDDB_API_KEY=$STEAMGRIDDB_API_KEY

# Background tasks
ENABLE_RESCAN_ON_FILESYSTEM_CHANGE=$ENABLE_RESCAN_ON_FILESYSTEM_CHANGE
RESCAN_ON_FILESYSTEM_CHANGE_DELAY=${RESCAN_DELAY:-5}
ENABLE_SCHEDULED_RESCAN=$ENABLE_SCHEDULED_RESCAN
SCHEDULED_RESCAN_CRON="${SCHEDULED_CRON:-"0 3 * * *"}"
ENABLE_SCHEDULED_UPDATE_SWITCH_TITLEDB=$ENABLE_SCHEDULED_UPDATE_SWITCH_TITLEDB
SCHEDULED_UPDATE_SWITCH_TITLEDB_CRON="${SWITCH_UPDATE_CRON:-"0 4 * * *"}"
EOF

# Create a basic config.yml file
cat <<EOF >/opt/romm/config/config.yml
# RomM Configuration
# Auto-generated during installation

# Path configuration
paths:
  library: /opt/romm/library
  assets: /opt/romm/assets
  resources: /opt/romm/resources
EOF

echo "Installed on $(date)" > /opt/romm/version.txt
msg_ok "Configured RomM Environment"

msg_info "Creating RomM Service"
# Create systemd service for RomM
cat <<EOF >/etc/systemd/system/romm.service
[Unit]
Description=RomM Application
After=network.target mariadb.service redis-server.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/romm/app
ExecStart=/opt/romm/venv/bin/python main.py
Restart=on-failure
Environment=PATH=/opt/romm/venv/bin:\$PATH
EnvironmentFile=/opt/romm/config/.env

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created RomM Service"

msg_info "Setting Permissions"
# Set permissions
chown -R www-data:www-data /opt/romm
msg_ok "Set Permissions"

msg_info "Starting Services"
# Enable and start services
systemctl daemon-reload
systemctl enable romm
systemctl start romm
msg_ok "Started Services"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

IP=$(hostname -I | awk '{print $1}')
msg_info "Installation Complete!"
echo -e "\n======================="
echo -e "${GN}RomM Installation Complete!${CL}"
echo -e "======================="
echo -e "${BL}Access RomM at:${CL} http://$IP:8080"
echo -e "\n${BL}Important information:${CL}"
echo -e "- Your database credentials are saved in: ~/romm.creds"
echo -e "- Your ROMs directory is: /opt/romm/library/roms"
echo -e "- Default ROM platforms created: gbc, gba, ps"
echo -e "- Default BIOS folders created: gba, ps"
echo -e "\n${YW}First time setup:${CL}"
echo -e "When you first access RomM, you'll need to create your admin account through the web interface."
echo -e "======================="
