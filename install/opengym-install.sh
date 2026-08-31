#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Hutti
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/arvids-unavailable/openGym

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# ─── Settings ────────────────────────────────────────────────────────────────
OG_REPO="https://github.com/arvids-unavailable/openGym"
OG_DIR="/opt/opengym"
OG_DATA="/opt/opengym-data"
OG_PORT="80"

msg_info "Installing Dependencies"
$STD apt install -y git nginx
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

msg_info "Fetching openGym (~150 MB, includes 1324 exercise images and GIFs)"
$STD git clone --depth 1 "$OG_REPO" "$OG_DIR"
# The repo ships a demo data/ folder containing a COMMITTED session secret and
# VAPID keys. Using them would sign every session cookie with a publicly known
# key, so it goes and real data lives outside the git tree instead.
rm -rf "${OG_DIR}/data"
mkdir -p "$OG_DATA"
chmod 700 "$OG_DATA"
msg_ok "Fetched openGym"

msg_info "Configuring openGym"
LOCAL_IP="$(hostname -I | awk '{print $1}')"
cat <<EOF >"${OG_DIR}/.env"
# openGym configuration - run "systemctl restart opengym" after changes.
#
# Passkeys (WebAuthn) only work over HTTPS or on http://localhost. Over
# http://<LAN-IP> the browser will not offer a passkey at all - guest mode
# still works. Behind a reverse proxy with a real hostname, set:
#   RP_ID=gym.example.com
#   ORIGIN=https://gym.example.com
RP_ID=${LOCAL_IP}
ORIGIN=http://${LOCAL_IP}
RP_NAME=openGym

PORT=3000
DATA_DIR=${OG_DATA}
SESSION_DAYS=90

# Comma-separated user ids that get the admin dashboard (empty = no admin)
#ADMIN_UIDS=
# Require an invite code to create a profile
#INVITE_ONLY=false
EOF
chmod 600 "${OG_DIR}/.env"
msg_ok "Configured openGym"

msg_info "Building Frontend (this takes a few minutes)"
cd "${OG_DIR}/frontend"
$STD npm ci
$STD npm run build
# ~220 MB of build-only deps; npm ci reinstalls them on every update anyway
rm -rf "${OG_DIR}/frontend/node_modules"
msg_ok "Built Frontend"

msg_info "Installing API"
cd "${OG_DIR}/api"
$STD npm ci --omit=dev
msg_ok "Installed API"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/opengym.service
[Unit]
Description=openGym API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${OG_DIR}/api
EnvironmentFile=${OG_DIR}/.env
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now opengym
msg_ok "Created Service"

msg_info "Configuring nginx"
rm -f /etc/nginx/sites-enabled/default
cat <<EOF >/etc/nginx/sites-available/opengym.conf
# openGym - serves the built app AND proxies /api to the backend, so the whole
# app lives on ONE origin (required for WebAuthn / passkeys).
server {
    listen ${OG_PORT};
    listen [::]:${OG_PORT};
    server_name _;

    root ${OG_DIR}/frontend/dist;
    index index.html;

    # State sync and history imports (FitNotes / Strong / Hevy / Apple Health)
    # post up to 5 MB; nginx's 1 MB default would reject them.
    client_max_body_size 10M;

    # ^~ on the three alias/proxy blocks: without it the regex block further
    # down wins and these get served from root instead.
    location ^~ /api/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ^~ /img/ {
        alias ${OG_DIR}/media/img/;
        expires 30d;
        add_header Cache-Control "public, max-age=2592000, immutable";
    }

    location ^~ /gif/ {
        alias ${OG_DIR}/media/gif/;
        expires 30d;
        add_header Cache-Control "public, max-age=2592000, immutable";
    }

    # SPA fallback
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # App shell: always revalidate so updates show up immediately
    location ~* \.(js|css|json|html)\$ {
        add_header Cache-Control "no-cache, must-revalidate";
    }

    gzip on;
    gzip_types text/plain text/css application/json application/javascript image/svg+xml;
    gzip_vary on;
    gzip_min_length 1024;
}
EOF
ln -sf /etc/nginx/sites-available/opengym.conf /etc/nginx/sites-enabled/opengym.conf
$STD nginx -t
systemctl restart nginx
msg_ok "Configured nginx"

msg_info "Saving Version"
git -C "$OG_DIR" rev-parse HEAD >/opt/opengym_version.txt
msg_ok "Saved Version"

motd_ssh
customize
cleanup_lxc
