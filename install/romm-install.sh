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

# Define key variables as documented in the setup guides
ROMM_INSTALL_DIR="/opt/romm"
ROMM_DATA_DIR="/var/lib/romm"
ROMM_CONFIG_DIR="${ROMM_DATA_DIR}/config"
ROMM_LIBRARY_DIR="${ROMM_DATA_DIR}/library"
ROMM_RESOURCES_DIR="${ROMM_DATA_DIR}/resources"
ROMM_ASSETS_DIR="${ROMM_DATA_DIR}/assets"
ROMM_BACKEND_DIR="${ROMM_INSTALL_DIR}/backend"
ROMM_FRONTEND_DIR="${ROMM_INSTALL_DIR}/frontend"

# User configurations
ROMM_USER="romm"
ROMM_GROUP="romm"

# Database configuration
DB_HOST="127.0.0.1"
DB_PORT="3306"
DB_NAME="romm"
DB_USER="romm"
# Generate secure password
DB_PASSWD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)
DB_ROOT_PASSWD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)

# Redis configuration
REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"
REDIS_PASSWORD=""

# Port configuration
FRONTEND_PORT=8080
BACKEND_PORT=5000

# Python version
PYTHON_VERSION="3.12"

# Node.js version
NODE_VERSION="18"

# Generate auth secret key
AUTH_SECRET_KEY=$(openssl rand -hex 32)

# Save credentials
mkdir -p ~/romm
{
    echo "RomM-Credentials"
    echo "RomM Database User: $DB_USER"
    echo "RomM Database Password: $DB_PASSWD"
    echo "RomM Database Name: $DB_NAME"
    echo "RomM Database Root Password: $DB_ROOT_PASSWD"
    echo "RomM Auth Secret Key: $AUTH_SECRET_KEY"
} > ~/romm/credentials.txt
chmod 600 ~/romm/credentials.txt

#########################################
# 1. SYSTEM DEPENDENCIES SETUP
#########################################

msg_info "Updating system packages"
$STD apt-get update
$STD apt-get upgrade -y
msg_ok "Updated system packages"

msg_info "Installing core dependencies"
$STD apt-get install -y \
    sudo \
    curl \
    wget \
    git \
    gnupg2 \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    lsb-release \
    unzip \
    tar \
    nano \
    acl \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3-dev \
    python3-pip \
    python3-venv \
    libmariadb3 \
    libmariadb-dev \
    libpq-dev \
    mariadb-client \
    redis-tools \
    p7zip \
    tzdata
msg_ok "Installed core dependencies"

msg_info "Creating ROMM user and group"
# Create group if it doesn't exist
if ! getent group ${ROMM_GROUP} > /dev/null; then
    groupadd -r ${ROMM_GROUP}
fi

# Create user if it doesn't exist
if ! id -u ${ROMM_USER} > /dev/null 2>&1; then
    useradd -r -g ${ROMM_GROUP} -d ${ROMM_DATA_DIR} -m -s /bin/bash ${ROMM_USER}
fi
msg_ok "Created ROMM user and group"

msg_info "Creating directory structure"
# Create main directories
mkdir -p ${ROMM_INSTALL_DIR}
mkdir -p ${ROMM_DATA_DIR}

# Create ROM directories with example console folders
mkdir -p ${ROMM_LIBRARY_DIR}/roms/gba
mkdir -p ${ROMM_LIBRARY_DIR}/roms/gbc
mkdir -p ${ROMM_LIBRARY_DIR}/roms/ps

# Create BIOS directories for specific consoles
mkdir -p ${ROMM_LIBRARY_DIR}/bios/gba
mkdir -p ${ROMM_LIBRARY_DIR}/bios/ps

# Create other required directories
mkdir -p ${ROMM_RESOURCES_DIR}
mkdir -p ${ROMM_ASSETS_DIR}/saves
mkdir -p ${ROMM_ASSETS_DIR}/states
mkdir -p ${ROMM_ASSETS_DIR}/screenshots
mkdir -p ${ROMM_CONFIG_DIR}

# Set permissions
chown -R ${ROMM_USER}:${ROMM_GROUP} ${ROMM_INSTALL_DIR}
chown -R ${ROMM_USER}:${ROMM_GROUP} ${ROMM_DATA_DIR}
msg_ok "Created directory structure"

msg_info "Setting system limits"
# Configure limits for ROMM user
cat > /etc/security/limits.d/romm.conf <<EOF
${ROMM_USER} soft nofile 65536
${ROMM_USER} hard nofile 65536
EOF
msg_ok "Set system limits"

#########################################
# 2. INSTALL PYTHON 3.12
#########################################

msg_info "Installing Python ${PYTHON_VERSION}"
# Add deadsnakes PPA for Python 3.12
$STD apt-get install -y software-properties-common
$STD add-apt-repository -y ppa:deadsnakes/ppa
$STD apt-get update

# Install Python 3.12
$STD apt-get install -y python3.12 python3.12-venv python3.12-dev

# Install pip for Python 3.12
$STD curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12

# Create symlinks
ln -sf /usr/bin/python3.12 /usr/bin/python3
ln -sf /usr/bin/python3 /usr/bin/python
msg_ok "Installed Python ${PYTHON_VERSION}"

msg_info "Installing Poetry"
# Install pipx first
$STD python3.12 -m pip install --user pipx
$STD python3.12 -m pipx ensurepath

# Install Poetry using pipx
$STD python3.12 -m pipx install poetry

# Configure Poetry
poetry config virtualenvs.in-project true
msg_ok "Installed Poetry"

#########################################
# 3. NODE.JS SETUP
#########################################

msg_info "Setting up Node.js Repository"
mkdir -p /etc/apt/keyrings
$STD curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION}.x nodistro main" >/etc/apt/sources.list.d/nodesource.list
msg_ok "Set up Node.js Repository"

msg_info "Installing Node.js"
$STD apt-get update
$STD apt-get install -y nodejs
msg_ok "Installed Node.js $(node -v)"

#########################################
# 4. DATABASE SETUP
#########################################

msg_info "Installing MariaDB server"
$STD apt-get install -y mariadb-server

# Secure MariaDB installation
$STD mysql_secure_installation <<EOF

y
${DB_ROOT_PASSWD}
${DB_ROOT_PASSWD}
y
y
y
y
EOF

# Start and enable MariaDB service
systemctl start mariadb
systemctl enable mariadb
msg_ok "Installed MariaDB server"

msg_info "Creating database and user"
# Create database and user with proper permissions
$STD mysql -u root -p"${DB_ROOT_PASSWD}" <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWD}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
EOF
msg_ok "Created database and user"

#########################################
# 5. REDIS SETUP
#########################################

msg_info "Installing Redis server"
$STD apt-get install -y redis-server

# Configure Redis
sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf

# Start and enable Redis service
systemctl restart redis-server
systemctl enable redis-server
msg_ok "Installed Redis server"

#########################################
# 6. REPOSITORY SETUP
#########################################

msg_info "Setting up ROMM repository"
# Get latest release version
RELEASE=$(curl -s https://api.github.com/repos/rommapp/romm/tags | jq --raw-output '.[0].name')

# Download and extract
wget -q https://codeload.github.com/rommapp/romm/tar.gz/refs/tags/${RELEASE} -O - | tar -xz 
mv romm-* ${ROMM_INSTALL_DIR}

# Set appropriate permissions
chown -R ${ROMM_USER}:${ROMM_GROUP} ${ROMM_INSTALL_DIR}
msg_ok "Set up ROMM repository v${RELEASE}"

#########################################
# 7. ENVIRONMENT CONFIGURATION
#########################################

msg_info "Creating environment configuration"
cat > ${ROMM_INSTALL_DIR}/.env <<EOF
# Base paths
ROMM_BASE_PATH=${ROMM_DATA_DIR}
DEV_MODE=false
KIOSK_MODE=false

# Gunicorn workers
WEB_CONCURRENCY=4

# Database config
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWD=${DB_PASSWD}
DB_ROOT_PASSWD=${DB_ROOT_PASSWD}

# Redis config
REDIS_HOST=${REDIS_HOST}
REDIS_PORT=${REDIS_PORT}
REDIS_PASSWORD=${REDIS_PASSWORD}

# Authentication
ROMM_AUTH_SECRET_KEY=${AUTH_SECRET_KEY}
DISABLE_DOWNLOAD_ENDPOINT_AUTH=false
DISABLE_CSRF_PROTECTION=false

# Filesystem watcher
ENABLE_RESCAN_ON_FILESYSTEM_CHANGE=true
RESCAN_ON_FILESYSTEM_CHANGE_DELAY=5

# Periodic Tasks
ENABLE_SCHEDULED_RESCAN=true
SCHEDULED_RESCAN_CRON=0 3 * * *
ENABLE_SCHEDULED_UPDATE_SWITCH_TITLEDB=true
SCHEDULED_UPDATE_SWITCH_TITLEDB_CRON=0 4 * * *

# Logging
LOGLEVEL=INFO
EOF

# Set appropriate permissions
chown ${ROMM_USER}:${ROMM_GROUP} ${ROMM_INSTALL_DIR}/.env
chmod 600 ${ROMM_INSTALL_DIR}/.env
msg_ok "Created environment configuration"

#########################################
# 8. BACKEND SETUP
#########################################

msg_info "Installing backend dependencies"
cd ${ROMM_INSTALL_DIR}
su - ${ROMM_USER} -c "cd ${ROMM_INSTALL_DIR} && python3.12 -m poetry install"
msg_ok "Installed backend dependencies"

msg_info "Running database migrations"
cd ${ROMM_BACKEND_DIR}
su - ${ROMM_USER} -c "cd ${ROMM_BACKEND_DIR} && PYTHONPATH=${ROMM_INSTALL_DIR} python3.12 -m poetry run alembic upgrade head"
msg_ok "Database migrations completed"

#########################################
# 9. FRONTEND SETUP
#########################################

msg_info "Installing frontend dependencies"
cd ${ROMM_FRONTEND_DIR}
su - ${ROMM_USER} -c "cd ${ROMM_FRONTEND_DIR} && npm install"
msg_ok "Installed frontend dependencies"

msg_info "Building frontend"
cd ${ROMM_FRONTEND_DIR}
su - ${ROMM_USER} -c "cd ${ROMM_FRONTEND_DIR} && npm run build"
msg_ok "Built frontend"

msg_info "Setting up resource links"
cd ${ROMM_FRONTEND_DIR}
# Remove existing links if they exist
rm -f assets/romm/resources
rm -f assets/romm/assets

# Create new links
ln -s ${ROMM_RESOURCES_DIR} ${ROMM_FRONTEND_DIR}/assets/romm/resources
ln -s ${ROMM_ASSETS_DIR} ${ROMM_FRONTEND_DIR}/assets/romm/assets
msg_ok "Set up resource links"

#########################################
# 10. SERVICE SETUP
#########################################

msg_info "Creating systemd services"
# Create backend API service
cat > /etc/systemd/system/romm-backend.service <<EOF
[Unit]
Description=ROMM Backend API Service
After=network.target mariadb.service redis-server.service
Requires=mariadb.service redis-server.service

[Service]
Type=simple
User=${ROMM_USER}
WorkingDirectory=${ROMM_BACKEND_DIR}
Environment="PYTHONPATH=${ROMM_INSTALL_DIR}"
ExecStart=/usr/local/bin/poetry run gunicorn main:app --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:${BACKEND_PORT}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Create worker service
cat > /etc/systemd/system/romm-worker.service <<EOF
[Unit]
Description=ROMM Background Worker Service
After=network.target mariadb.service redis-server.service romm-backend.service
Requires=mariadb.service redis-server.service

[Service]
Type=simple
User=${ROMM_USER}
WorkingDirectory=${ROMM_BACKEND_DIR}
Environment="PYTHONPATH=${ROMM_INSTALL_DIR}"
ExecStart=/usr/local/bin/poetry run python3 worker.py
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Create scheduler service
cat > /etc/systemd/system/romm-scheduler.service <<EOF
[Unit]
Description=ROMM Scheduler Service
After=network.target mariadb.service redis-server.service romm-backend.service
Requires=mariadb.service redis-server.service

[Service]
Type=simple
User=${ROMM_USER}
WorkingDirectory=${ROMM_BACKEND_DIR}
Environment="PYTHONPATH=${ROMM_INSTALL_DIR}"
ExecStart=/usr/local/bin/poetry run python3 scheduler.py
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Create frontend service
cat > /etc/systemd/system/romm-frontend.service <<EOF
[Unit]
Description=ROMM Frontend Service
After=network.target

[Service]
Type=simple
User=${ROMM_USER}
WorkingDirectory=${ROMM_FRONTEND_DIR}
ExecStart=$(which serve) -s dist -l ${FRONTEND_PORT}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Install serve globally
su - ${ROMM_USER} -c "npm install -g serve"

# Reload systemd, enable and start services
systemctl daemon-reload
systemctl enable romm-backend.service
systemctl enable romm-worker.service
systemctl enable romm-scheduler.service
systemctl enable romm-frontend.service
msg_ok "Created systemd services"

msg_info "Starting services"
systemctl start romm-backend.service
systemctl start romm-worker.service
systemctl start romm-scheduler.service
systemctl start romm-frontend.service
msg_ok "Started services"

#########################################
# 11. VALIDATION
#########################################

msg_info "Verifying services"
SERVICE_ERROR=0

# Check if services are active
if ! systemctl is-active --quiet romm-backend.service; then
    msg_error "Backend API service is not running"
    SERVICE_ERROR=1
fi

if ! systemctl is-active --quiet romm-worker.service; then
    msg_error "Worker service is not running"
    SERVICE_ERROR=1
fi

if ! systemctl is-active --quiet romm-scheduler.service; then
    msg_error "Scheduler service is not running"
    SERVICE_ERROR=1
fi

if ! systemctl is-active --quiet romm-frontend.service; then
    msg_error "Frontend service is not running"
    SERVICE_ERROR=1
fi

# Check if ports are open
if ! timeout 2 bash -c "cat < /dev/null > /dev/tcp/localhost/${BACKEND_PORT}" 2>/dev/null; then
    msg_error "Backend API port ${BACKEND_PORT} is not accessible"
    SERVICE_ERROR=1
fi

if ! timeout 2 bash -c "cat < /dev/null > /dev/tcp/localhost/${FRONTEND_PORT}" 2>/dev/null; then
    msg_error "Frontend port ${FRONTEND_PORT} is not accessible"
    SERVICE_ERROR=1
fi

if [ $SERVICE_ERROR -eq 0 ]; then
    msg_ok "All services are running correctly"
fi

#########################################
# 12. CLEANUP AND FINISH
#########################################

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
$STD apt-get -y clean
msg_ok "Cleaned"

IP=$(hostname -I | awk '{print $1}')
msg_info "Installation Complete!"
echo -e "\n======================="
echo -e "RomM Installation Complete!"
echo -e "======================="
echo -e "Access RomM at: http://$IP:${FRONTEND_PORT}"
echo -e "\n- Your credentials are saved in: ~/romm/credentials.txt"
echo -e "- Your ROMs directory is: ${ROMM_LIBRARY_DIR}/roms"
echo -e "======================="
