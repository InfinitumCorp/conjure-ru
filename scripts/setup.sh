#!/bin/bash
# Conjure Russia on Yandex (conjure-russia, Ubuntu 24.04). No Claude: no ANTHROPIC_API_KEY ever.
# Live only: without CONJURE_LLM_* it refuses builds and forecasts (no demo mode). Re-runnable; safe to run again to upgrade.
set -euo pipefail
# Conjure commit to run. Bump this (full 40-char SHA from InfinitumCorp/Conjure main) to upgrade.
SHA=${CONJURE_SHA:-74c37b59b2ba8bc9a9e26bf238321d689e04ca50}
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
# Models: open-weight models on Yandex Cloud AI Studio, inside Russia. Empty = no builds or forecasts.
# setup.sh fills these in when CONJURE_LLM_KEY is passed. Never add ANTHROPIC_API_KEY on this server,
# and never point CONJURE_LLM_URL at a server outside Russia (setup.sh refuses both).
# CONJURE_LLM_URL=https://ai.api.cloud.yandex.net/v1
# CONJURE_LLM_KEY=
# CONJURE_LLM_PROJECT=
# CONJURE_LLM_MODEL=gpt://<folder>/qwen3.6-35b-a3b
# CONJURE_LLM_REASONING=
EOF
fi

# Models: Conjure Russia runs 100% in Russia, models included. Predictions and code generation use
# open-weight models on Yandex Cloud AI Studio (Russian data centers), billed to the Yandex account.
# Pass an AI Studio API key (service account with ai.languageModels.user) to set or replace it:
#   read -rs CONJURE_LLM_KEY && export CONJURE_LLM_KEY && bash scripts/setup.sh
# It is written root-only and never printed. Without a model the server refuses work (live only).
YANDEX_FOLDER=${YANDEX_FOLDER:-b1g3bonfmtl53fs762er}
YANDEX_URL=https://ai.api.cloud.yandex.net/v1
# Qwen3.6 35B (Apache 2.0, 256k context): AI Studio's current open-weight model. gpt-oss was
# withdrawn on 2026-10-30. List what the folder can use with GET $YANDEX_URL/models.
YANDEX_MODEL=${CONJURE_LLM_MODEL:-gpt://$YANDEX_FOLDER/qwen3.6-35b-a3b}
set_env() { # name value: replace or append one line in /etc/conjure/env
  local tmp
  tmp=$(sudo mktemp)
  sudo grep -v "^$1=" /etc/conjure/env | sudo tee "$tmp" >/dev/null || true
  printf '%s=%s\n' "$1" "$2" | sudo tee -a "$tmp" >/dev/null
  sudo install -m 0600 "$tmp" /etc/conjure/env
  sudo rm -f "$tmp"
}
unset_env() { # name: remove a line from /etc/conjure/env
  local tmp
  tmp=$(sudo mktemp)
  sudo grep -v "^$1=" /etc/conjure/env | sudo tee "$tmp" >/dev/null || true
  sudo install -m 0600 "$tmp" /etc/conjure/env
  sudo rm -f "$tmp"
}
# Preferred: no key at all. With a service account attached to this VM (conjure-models, role
# ai.languageModels.user), Conjure signs each call with the VM's own short-lived IAM token:
#   CONJURE_LLM_AUTH=yandex-vm bash scripts/setup.sh
# setup.sh checks the VM can get a token before switching.
if [ "${CONJURE_LLM_AUTH:-}" = yandex-vm ]; then
  curl -fsS --max-time 5 -o /dev/null -H Metadata-Flavor:Google \
    http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token \
    || { log "no service account on this VM: attach one (ai.languageModels.user) or pass CONJURE_LLM_KEY"; exit 1; }
  set_env CONJURE_LLM_AUTH yandex-vm
  unset_env CONJURE_LLM_KEY
  CONJURE_LLM_KEY=vm # takes the branch below; never written
fi
if [ -n "${CONJURE_LLM_KEY:-}" ]; then
  set_env CONJURE_LLM_URL "$YANDEX_URL"
  if [ "$CONJURE_LLM_KEY" != vm ]; then set_env CONJURE_LLM_KEY "$CONJURE_LLM_KEY"; unset_env CONJURE_LLM_AUTH; fi
  set_env CONJURE_LLM_PROJECT "$YANDEX_FOLDER"
  set_env CONJURE_LLM_MODEL "$YANDEX_MODEL"
  # Thinking is on (William, 2026-11-12). It used to be off ("none") because Qwen3.6 spent ~1,400
  # tokens thinking about 2+2 and real prompts ran out of tokens before the JSON answer; Conjure
  # 74c37b5 gives every call CONJURE_LLM_THINK_TOKENS (default 4096) on top of its answer budget.
  # Pass CONJURE_LLM_REASONING=low|high to change the level, or none to turn thinking off.
  set_env CONJURE_LLM_REASONING "${CONJURE_LLM_REASONING:-medium}"
  log "models: Yandex AI Studio, ${YANDEX_MODEL#gpt://*/}"
fi
# The global hostname (front/, a Cloudflare Worker) forwards here; staff who sign in through it are
# sent back to it. It must also be on the conjure client's allow-list in Cumulus ID.
set_env CONJURE_FRONT_HOSTS conjure.infinitumcorporation.ai
# The Cloudflare gateway's Access token has no place here: everything stays in Russia.
unset_env CONJURE_LLM_ACCESS_ID
unset_env CONJURE_LLM_ACCESS_SECRET

# Guards: this server must never talk to Claude or send prompts to a model outside Russia.
if sudo grep -q '^ANTHROPIC_API_KEY=' /etc/conjure/env; then
  echo "[conjure] ANTHROPIC_API_KEY must never be set on the Russia server; remove it from /etc/conjure/env" >&2
  exit 1
fi
russian_host() { # URL: Yandex Cloud or this machine
  local host
  host=$(printf '%s' "$1" | sed -E 's#^[a-z]+://##; s#[/:].*$##')
  case "$host" in
    *.yandex.net | *.yandexcloud.net | *.yandex.ru | *.yandex.cloud | localhost | 127.0.0.1) return 0 ;;
    *) return 1 ;;
  esac
}
for var in CONJURE_LLM_URL CONJURE_OPEN_WEIGHTS_URL; do
  urls=$(sudo grep "^$var=" /etc/conjure/env | cut -d= -f2- || true)
  for u in ${urls//,/ }; do
    if ! russian_host "$u"; then
      echo "[conjure] $var points outside Russia ($u); Conjure Russia keeps every model call in Russia" >&2
      exit 1
    fi
  done
done

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
for _ in $(seq 1 30); do curl -fsS http://127.0.0.1:4317/healthz >/dev/null 2>&1 && break; sleep 1; done
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
