#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/DevelopmentCats/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 DevelopmentCats
# Author: DevelopmentCats
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://romm.app
# Updated: 03/10/2025

APP="RomM"
var_tags="emulation;manager"
var_cpu="2"
var_ram="4096"
var_disk="20"
var_os="ubuntu"
var_version="22.04"
var_unprivileged="1"
var_swap="4096"
var_features="fuse=1,nesting=1,keyctl=1,mount=1"
var_port_map="8080:8080,5000:5000"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -d /opt/romm ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    msg_info "Stopping $APP"
    systemctl stop romm
    systemctl stop nginx
    msg_ok "Stopped $APP"

    msg_info "Updating $APP"
    cd /opt/romm/app
    git pull

    # Update backend
    cd /opt/romm/app
    source /opt/romm/venv/bin/activate
    pip install --upgrade pip
    pip install poetry
    poetry install

    # Update frontend
    cd /opt/romm/app/frontend
    npm install
    npm run build

    echo "Updated on $(date)" >/opt/romm/version.txt
    msg_ok "Updated $APP"

    msg_info "Starting $APP"
    systemctl start romm
    systemctl start nginx
    msg_ok "Started $APP"
    msg_ok "Update Successful"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
