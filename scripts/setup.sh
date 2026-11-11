#!/bin/bash
# Conjure Russia on Yandex (conjure-russia, Ubuntu 24.04). No Claude: no ANTHROPIC_API_KEY ever.
# Without CONJURE_LLM_* it runs on the mock provider. Re-runnable; safe to run again to upgrade.
set -euo pipefail
# Conjure commit to run. Bump this (full 40-char SHA from InfinitumCorp/Conjure main) to upgrade.
SHA=${CONJURE_SHA:-1da489e5e9babe65228280bcf552ab458ef58bbb}
APP=conjure-ru.infinitumcorporation.ai
PREVIEW=conjure-ru-preview.infinitumcorporation.ai
MYIP=51.250.92.75
NODE_VERSION=v24.11.0
log() { echo "[conjure] $*"; }
TMP=$(mktemp -d)

sudo DEBIAN_FRONTEND=noninteractive apt-get -qq update >/dev/null
sudo DEBIAN_FRONTEND=noninteractive apt-get -qq install -y nginx certbot xz-utils >/dev/null

# Node (official build, checksum-verified)
if [ "$(/usr/local/bin/node -v 2>/dev/null || true)" != "$NODE_VERSION" ]; then
  f="node-$NODE_VERSION-linux-x64.tar.xz"
  curl -fsSL -o "$TMP/$f" "https://nodejs.org/dist/$NODE_VERSION/$f"
  curl -fsSL -o "$TMP/SHASUMS256.txt" "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt"
  (cd "$TMP" && grep " $f\$" SHASUMS256.txt | sha256sum -c - >/dev/null)
  sudo tar -xJf "$TMP/$f" -C /usr/local --strip-components=1 --no-same-owner
fi
log "node $(/usr/local/bin/node -v)"

id conjure >/dev/null 2>&1 || sudo useradd --system --home-dir /var/lib/conjure --shell /usr/sbin/nologin conjure
sudo install -d -o conjure -g conjure -m 0750 /var/lib/conjure
sudo install -d -o conjure -g conjure -m 0700 /var/lib/conjure-data
sudo install -d -m 0755 /opt/conjure/releases /var/www/acme
sudo install -d -m 0700 /etc/conjure

# Code: InfinitumCorp/Conjure at a pinned commit
REL=/opt/conjure/releases/$SHA
if ! sudo test -f "$REL/src/server.js"; then
  sudo mkdir -p "$REL"
  curl -fsSL "https://codeload.github.com/InfinitumCorp/Conjure/tar.gz/$SHA" | sudo tar -xz --strip-components=1 -C "$REL" --no-same-owner
  (cd "$REL" && sudo env PATH=/usr/local/bin:$PATH npm ci --omit=dev --no-audit --no-fund --loglevel=error)
  sudo chown -R root:root "$REL"; sudo chmod -R a+rX "$REL"
fi
sudo ln -sfn "$REL" /opt/conjure/current
log "code $SHA"

# Secrets: root-only, created once. The access token turns sign-in on (fail closed until CID_OWNERS is set).
if ! sudo test -f /etc/conjure/env; then
  TOKEN=$(openssl rand -hex 32)
  sudo install -m 0600 /dev/null /etc/conjure/env
  sudo tee /etc/conjure/env >/dev/null <<EOF
# Conjure Russia. Root-only (600). Never commit or print.
CONJURE_ACCESS_TOKEN=$TOKEN
CONJURE_PUBLIC_URL=https://$APP
# Owner: your Cumulus ID (cid_...). Until this is set nobody can sign in.
# CID_OWNERS=
# A Cumulus ID mirror that loads in Russia, if id.cumuluscloud.app does not:
# CID_ISSUER=
# Predictions without Claude (open-weight models via the conjure-llm gateway). Empty = mock provider.
# Never add ANTHROPIC_API_KEY on this server.
# CONJURE_LLM_URL=
# CONJURE_LLM_KEY=
# CONJURE_LLM_ACCESS_ID=
# CONJURE_LLM_ACCESS_SECRET=
# CONJURE_LLM_MODEL=@cf/qwen/qwen3-30b-a3b-fp8
# CONJURE_LLM_REASONING=none
EOF
fi

sudo tee /etc/systemd/system/conjure.service >/dev/null <<EOF
[Unit]
Description=Conjure (Russia)
After=network-online.target
Wants=network-online.target

[Service]
User=conjure
Group=conjure
WorkingDirectory=/opt/conjure/current
EnvironmentFile=/etc/conjure/env
Environment=NODE_ENV=production HOST=127.0.0.1 PORT=4317 PREVIEW_PORT=4318
Environment=CONJURE_OUT=/var/lib/conjure CONJURE_DATA=/var/lib/conjure-data PREVIEW_ORIGIN=https://$PREVIEW
ExecStart=/usr/local/bin/node src/server.js
Restart=always
RestartSec=2
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/conjure /var/lib/conjure-data
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable conjure >/dev/null 2>&1
sudo systemctl restart conjure
for i in $(seq 1 30); do curl -fsS http://127.0.0.1:4317/healthz >/dev/null 2>&1 && break; sleep 1; done
log "healthz: $(curl -s http://127.0.0.1:4317/healthz)"
log "/ without login: $(curl -s -o /dev/null -w '%{http_code} -> %{redirect_url}' http://127.0.0.1:4317/)"
log "mode: $(sudo journalctl -u conjure --no-pager -n 20 | grep -oE '(live|offline)[^\"]*' | tail -1)"

# HTTP: ACME challenges only, everything else to HTTPS
sudo tee /etc/nginx/sites-available/default >/dev/null <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    server_tokens off;
    location /.well-known/acme-challenge/ { root /var/www/acme; }
    location / { return 301 https://\$host\$request_uri; }
}
EOF
sudo nginx -t -q && sudo systemctl reload nginx

# HTTPS: only once both names point here
# Retried: a single lookup can fail on a resolver blip.
resolves() {
  for _ in 1 2 3 4 5; do
    [ "$(getent ahostsv4 "$1" | awk '{print $1; exit}')" = "$MYIP" ] && return 0
    sleep 3
  done
  return 1
}
if ! resolves $APP || ! resolves $PREVIEW; then
  log "DNS for $APP / $PREVIEW does not point at $MYIP yet; HTTPS skipped"
  exit 0
fi
if ! sudo test -f /etc/letsencrypt/live/$APP/fullchain.pem; then
  sudo certbot certonly --webroot -w /var/www/acme -d $APP -d $PREVIEW --non-interactive --agree-tos --register-unsafely-without-email --quiet
fi
proxy() { cat <<EOF
        proxy_pass http://127.0.0.1:$1;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_buffering off;
        proxy_read_timeout 3600s;
EOF
}
sudo tee /etc/nginx/sites-available/conjure-russia >/dev/null <<EOF
map \$http_upgrade \$connection_upgrade { default upgrade; '' close; }
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $APP;
    server_tokens off;
    ssl_certificate     /etc/letsencrypt/live/$APP/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$APP/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    add_header Strict-Transport-Security "max-age=31536000" always;
    client_max_body_size 50M;
    gzip on;
    location / {
$(proxy 4317)
    }
}
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $PREVIEW;
    server_tokens off;
    ssl_certificate     /etc/letsencrypt/live/$APP/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$APP/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 50M;
    location / {
$(proxy 4318)
    }
}
EOF
sudo ln -sf /etc/nginx/sites-available/conjure-russia /etc/nginx/sites-enabled/conjure-russia
sudo nginx -t -q && sudo systemctl reload nginx
echo -e '#!/bin/sh\nsystemctl reload nginx' | sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh >/dev/null
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
log "cert: $(sudo openssl x509 -in /etc/letsencrypt/live/$APP/fullchain.pem -noout -enddate)"
