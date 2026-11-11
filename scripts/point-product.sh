#!/usr/bin/env bash
# Points one Infinitum product's Cloudflare Worker at Conjure Russia.
#
# Run from the product's folder (the one with its wrangler config), after issuing the product's key
# in the Conjure dashboard (Product keys → Issue). The key is read at a silent prompt and handed
# straight to `wrangler secret put`; it is never printed, logged or written to disk.
#
#   bash ../conjure-ru/scripts/point-product.sh                 # CONJURE_URL + CONJURE_PRODUCT_KEY
#   KEY_VAR=CONJURE_KEY bash ../conjure-ru/scripts/point-product.sh   # FIRM Wallet's key name
#
# CONJURE_URL defaults to the global hostname, which reaches the Russian server from every network.
set -euo pipefail

URL="${CONJURE_URL:-https://conjure.infinitumcorporation.ai}"
URL_VAR="${URL_VAR:-CONJURE_URL}"
KEY_VAR="${KEY_VAR:-CONJURE_PRODUCT_KEY}"

case "$URL" in
  https://conjure.infinitumcorporation.ai|https://conjure-ru.infinitumcorporation.ai) ;;
  *) echo "CONJURE_URL must be the global or the Russian hostname, not $URL" >&2; exit 1 ;;
esac
ls wrangler.json wrangler.jsonc wrangler.toml >/dev/null 2>&1 \
  || { echo "Run this from the product's folder (no wrangler config here)." >&2; exit 1; }

curl -fsS --max-time 20 "$URL/healthz" >/dev/null || { echo "Conjure isn't answering at $URL" >&2; exit 1; }

printf 'Product key (cjp_...), hidden: ' >&2
read -rs KEY; echo >&2
[[ "$KEY" =~ ^cjp_[a-z]+_[A-Za-z0-9_-]+$ ]] || { echo "That doesn't look like a product key (cjp_<product>_...)." >&2; exit 1; }

# The key must work before it's stored. /v1/health answers 200 only to a valid product key.
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -H "authorization: Bearer $KEY" "$URL/v1/health")
[ "$code" = 200 ] || { unset KEY; echo "Conjure refused the key (HTTP $code); nothing was changed." >&2; exit 1; }

printf '%s' "$URL" | npx wrangler secret put "$URL_VAR"
printf '%s' "$KEY" | npx wrangler secret put "$KEY_VAR"
unset KEY
echo "Done: $URL_VAR and $KEY_VAR are set on this Worker."
