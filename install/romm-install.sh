#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: DevelopmentCats
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://romm.app

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
    nginx \
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

msg_info "Setting up RomM"
# Create directories
mkdir -p /opt/romm
mkdir -p /opt/romm/library
mkdir -p /opt/romm/assets
mkdir -p /opt/romm/config
mkdir -p /opt/romm/resources

# Clone the repository
git clone https://github.com/rommapp/romm.git /opt/romm/app

# Set up Python virtual environment
python3 -m venv /opt/romm/venv
source /opt/romm/venv/bin/activate
pip install --upgrade pip
pip install poetry

# Install backend dependencies
cd /opt/romm/app
poetry install

# Build frontend
cd /opt/romm/app/frontend
npm install
npm run build

# Create environment configuration
cat > /opt/romm/config/.env << EOF
DB_HOST=localhost
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWD=$DB_PASS
ROMM_AUTH_SECRET_KEY=$AUTH_SECRET_KEY
IGDB_CLIENT_ID=
IGDB_CLIENT_SECRET=
MOBYGAMES_API_KEY=
STEAMGRIDDB_API_KEY=
EOF

echo "Installed on $(date)" > /opt/romm/version.txt
msg_ok "Set up RomM"

msg_info "Creating Service"
# Create systemd service for RomM
cat > /etc/systemd/system/romm.service << EOF
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

# Configure Nginx
cat > /etc/nginx/sites-available/romm << EOF
server {
    listen 8080;
    server_name _;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -s /etc/nginx/sites-available/romm /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Set permissions
chown -R www-data:www-data /opt/romm

# Enable and start services
systemctl daemon-reload
systemctl enable romm
systemctl enable nginx
systemctl start romm
systemctl restart nginx
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
