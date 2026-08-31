#!/usr/bin/env bash
# Point this at YOUR repo (raw base URL, no trailing slash). It is what the
# container's `update` command pulls ct/opengym.sh from later on.
_CS_DEFAULT_URL="${_CS_DEFAULT_URL:-https://raw.githubusercontent.com/hutti207/ProxmoxVE/main}"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Hutti
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/arvids-unavailable/openGym

APP="openGym"
var_tags="${var_tags:-fitness;tracker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/opengym ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ensure_dependencies git nginx
  NODE_VERSION="22" setup_nodejs

  # openGym publishes no releases or tags, so the commit on main is the version.
  RELEASE=$(git ls-remote https://github.com/arvids-unavailable/openGym HEAD | awk '{print $1}')
  if [[ -z "$RELEASE" ]]; then
    msg_error "Could not reach GitHub"
    exit
  fi

  if [[ "${RELEASE}" != "$(cat /opt/opengym_version.txt 2>/dev/null)" ]]; then
    msg_info "Stopping Services"
    systemctl stop opengym nginx
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    tar -czf "/opt/opengym-data-backup-$(date +%F_%H%M).tar.gz" -C /opt opengym-data
    cp /opt/opengym/.env /opt/opengym.env.bak
    msg_ok "Backed up Data"

    msg_info "Updating ${APP}"
    cd /opt/opengym
    $STD git fetch --depth 1 origin main
    $STD git reset --hard FETCH_HEAD
    # The repo's demo data/ folder comes back with every reset - drop it again.
    rm -rf /opt/opengym/data
    cp /opt/opengym.env.bak /opt/opengym/.env
    cd /opt/opengym/frontend
    $STD npm ci
    $STD npm run build
    rm -rf /opt/opengym/frontend/node_modules
    cd /opt/opengym/api
    $STD npm ci --omit=dev
    echo "${RELEASE}" >/opt/opengym_version.txt
    msg_ok "Updated ${APP}"

    msg_info "Starting Services"
    systemctl start opengym nginx
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  else
    systemctl start opengym nginx
    msg_ok "No update required. ${APP} is already up to date"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
