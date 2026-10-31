#!/usr/bin/env bash
# Point this at YOUR repo (raw base URL, no trailing slash). It is what the
# container's `update` command pulls ct/opengym.sh from later on.
_CS_DEFAULT_URL="${_CS_DEFAULT_URL:-https://raw.githubusercontent.com/hutti207/ProxmoxVE/main}"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/DuarteSantos8/openGym

APP="openGym"
var_tags="${var_tags:-health;fitness}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
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
    msg_error "No openGym Installation Found!"
    exit
  fi

  if check_for_gh_release "opengym" "DuarteSantos8/openGym" "" "" "v"; then
    msg_info "Stopping openGym"
    systemctl stop nginx opengym
    msg_ok "Stopped openGym"

    # Containers set up by this fork's first script ran a git checkout of the
    # arvids-unavailable/openGym copy: .env inside /opt/opengym, data in
    # /opt/opengym-data. CLEAN_INSTALL wipes /opt/opengym, so move config and data
    # to the layout of the current install script first.
    if [[ -f /opt/opengym/.env && ! -f /opt/opengym_data/.env ]]; then
      msg_info "Migrating openGym to the new layout"
      tar -czf "/opt/opengym-migration-backup-$(date +%F_%H%M).tar.gz" -C /opt opengym-data opengym/.env
      mkdir -p /opt/opengym_data
      cp -a /opt/opengym-data/. /opt/opengym_data/
      {
        echo "PORT=3000"
        echo "DATA_DIR=/opt/opengym_data"
        grep -Ev '^[[:space:]]*(#|$)|^(PORT|DATA_DIR)=' /opt/opengym/.env || true
        grep -q '^PASSWORD_LOGIN=' /opt/opengym/.env || echo "PASSWORD_LOGIN=1"
        grep -q '^FIRST_USER_ADMIN=' /opt/opengym/.env || echo "FIRST_USER_ADMIN=1"
      } >/opt/opengym_data/.env
      chmod 600 /opt/opengym_data/.env
      cat <<EOF >/etc/systemd/system/opengym.service
[Unit]
Description=openGym API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/opengym/api
EnvironmentFile=/opt/opengym_data/.env
Environment=NODE_ENV=production
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
      rm -f /etc/nginx/sites-enabled/opengym.conf /etc/nginx/sites-available/opengym.conf
      cat <<'EOF' >/etc/nginx/sites-available/opengym
server {
    listen 80 default_server;
    server_name _;
    root /opt/opengym/frontend/dist;
    index index.html;
    absolute_redirect off;

    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "same-origin" always;
    add_header Content-Security-Policy "frame-ancestors 'none'" always;

    location ^~ /api/ {
        client_max_body_size 5m;
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header CF-Connecting-IP "";
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location ^~ /api/media/ {
        client_max_body_size 48m;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header CF-Connecting-IP "";
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location / {
        try_files $uri $uri/ @root;
    }

    location @root {
        return 302 /$is_args$args;
    }

    location ~* \.(js|css|json|html)$ {
        add_header Cache-Control "no-cache, must-revalidate";
        add_header X-Frame-Options "DENY" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "same-origin" always;
        add_header Content-Security-Policy "frame-ancestors 'none'" always;
    }

    location ^~ /exercise-media/ {
        alias /opt/opengym/catalogue/media/;
        add_header Cache-Control "public, max-age=2592000, immutable";
        add_header Cross-Origin-Resource-Policy "same-origin" always;
        add_header X-Frame-Options "DENY" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "same-origin" always;
        add_header Content-Security-Policy "frame-ancestors 'none'" always;
    }

    location ~* \.(png|jpg|jpeg|gif|ico|svg|woff|woff2|webp|avif|mp4)$ {
        add_header Cache-Control "public, max-age=2592000, immutable";
        add_header X-Frame-Options "DENY" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "same-origin" always;
        add_header Content-Security-Policy "frame-ancestors 'none'" always;
    }

    gzip on;
    gzip_types text/plain text/css application/json application/javascript image/svg+xml;
    gzip_vary on;
    gzip_min_length 1024;
}
EOF
      systemctl daemon-reload
      nginx_enable_site "opengym"
      rm -f /opt/opengym_version.txt /opt/opengym.env.bak
      msg_ok "Migrated openGym (old data kept in /opt/opengym-data)"
    fi

    NODE_VERSION="22" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "opengym" "DuarteSantos8/openGym" "tarball" "latest" "/opt/opengym" "" "v"

    msg_info "Building openGym"
    cd /opt/opengym/api
    $STD npm ci --omit=dev --omit=optional
    cd /opt/opengym/frontend
    $STD npm ci --ignore-scripts
    $STD npm run build
    rm -rf /opt/opengym/frontend/node_modules ~/.npm
    msg_ok "Built openGym"

    msg_info "Starting openGym"
    systemctl start opengym nginx
    msg_ok "Started openGym"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
echo -e "${INFO}${YW}Sign-in is by password over plain HTTP. Create your profile right away: the first one becomes the admin.${CL}"
echo -e "${INFO}${YW}For passkeys, serve it over HTTPS on a hostname through a reverse proxy, then set RP_ID and ORIGIN in /opt/opengym_data/.env and run systemctl restart opengym. Changing RP_ID later invalidates existing passkeys.${CL}"
