# conjure-ru: Conjure Russia

The Russia version of Conjure™: its own server on Yandex Cloud at **https://conjure-ru.infinitumcorporation.ai** (VM `conjure-russia`, zone ru-central1-a, static IP).

The application code stays in [InfinitumCorp/Conjure](https://github.com/InfinitumCorp/Conjure) and is pinned here by commit. This repo holds what is different for Russia.

## What is different from the main deployment

| | Russia |
|---|---|
| Hosting | Yandex Cloud, nginx + Let's Encrypt in front of Node on 127.0.0.1 |
| Model provider | **100% in Russia, no Claude.** Predictions and code generation run on open-weight models on **Yandex Cloud AI Studio** (default Qwen3.6 35B, Apache 2.0, 256k context; AI Studio withdrew gpt-oss on 2026-10-30), in Russian data centers. `setup.sh` refuses to run if `ANTHROPIC_API_KEY` is set or a model URL points outside Russia, and removes any Cloudflare gateway settings. AI Studio bills per token to the Yandex account (see its [pricing page](https://aistudio.yandex.ru/docs/en/ai-studio/pricing.html)); the account's 4,000 ₽ starter grant covers it at first. With no `CONJURE_LLM_KEY` it runs on the mock provider |
| Sign-in | Required (`CONJURE_ACCESS_TOKEN` set). Sign in with Cumulus ID; only IDs in `CID_OWNERS` get in (no staff list) |
| Preview | Separate host `conjure-ru-preview.infinitumcorporation.ai` (127.0.0.1:4318) |
| Backups | Yandex disk snapshot daily at 00:00 UTC, 7 kept |

## Global hostname

**https://conjure.infinitumcorporation.ai** reaches the same server from networks that block Yandex Cloud's address range (in a worldwide probe, 3 of 40 networks failed to reach the server directly). It is a Cloudflare Worker (`front/`) that forwards every request to `conjure-ru.infinitumcorporation.ai` over HTTPS. It stores nothing and runs no model; Conjure, its data and its models stay on the Russian server.

- Products outside Russia should use the global hostname as `CONJURE_URL`; products in Russia can use either.
- Cloudflare terminates TLS for the global hostname, so traffic through it is decrypted in transit on Cloudflare's network before being re-encrypted to the server. Use `conjure-ru.infinitumcorporation.ai` directly where that matters.
- The account's "All Workers" Access app covers every Worker, so the hostname needs its own public Access app ("Conjure global front (public)", bypass for everyone), as the other public sites have. Conjure's own sign-in still applies behind it.
- The server sees Cloudflare's addresses for front traffic, so its guessing lockout counts by those addresses.
- Deploy: `cd front && npm ci && npx cf deploy`. Test: `node --test test/`.

### Pointing products at Conjure

Each product needs `CONJURE_URL` and its own product key. Issue the key in the dashboard (Product keys → Issue; it is shown once), then from the product's folder run `bash ../conjure-ru/scripts/point-product.sh` and paste the key at the hidden prompt. The script checks that Conjure accepts the key, then stores both values with `wrangler secret put`.

| Product | Folder | Key setting |
|---|---|---|
| :\ARCHITECT\ | `architect` | `CONJURE_PRODUCT_KEY` (default) |
| Cumulus://Mail | `cumulus-mail` | `CONJURE_PRODUCT_KEY` (default) |
| +SPCTR | `infinitum-nexus/apps/spectre` | `CONJURE_PRODUCT_KEY` (default) |
| FIRM Wallet | `infinitum-nexus/apps/firm-wallet` | `KEY_VAR=CONJURE_KEY` |

SCALVS.ai is not on the list: its `CONJURE_URL` setting expects a MiroFish-style engine, not Conjure's `/v1` API, and it forecasts on its own engine until it is ported.

Wait until the server runs real models (a Yandex key is set); in mock mode every product would get placeholder forecasts.

## Layout

- `scripts/setup.sh`: Node (checksum-verified), the pinned Conjure release in `/opt/conjure/releases/<sha>`, the sandboxed `conjure` systemd service, nginx and TLS. Re-runnable.
- `scripts/check.sh`: outside checks; also runs from the `check` workflow on demand.
- `front/`: the global hostname's forwarding Worker.

## Deploy or upgrade

Bump `SHA` in `scripts/setup.sh` (or pass `CONJURE_SHA=<full sha>`), then on the server:

```bash
ssh conjure-russia
git clone https://github.com/InfinitumCorp/conjure-ru && cd conjure-ru   # or: git pull
bash scripts/setup.sh
```

Old releases stay in `/opt/conjure/releases`; to roll back, run it again with the previous SHA.

## Server settings (`/etc/conjure/env`, root-only, never committed)

Created once by `setup.sh` with a random `CONJURE_ACCESS_TOKEN`. Fill in on the server, then `sudo systemctl restart conjure`:

- `CID_OWNERS`: the Cumulus IDs (`cid_...`) allowed in. Until set, nobody can sign in.
- `CID_ISSUER` (optional): a Cumulus ID mirror, only if id.cumuluscloud.app stops loading from Russia.
- `CONJURE_LLM_URL`, `CONJURE_LLM_KEY`, `CONJURE_LLM_PROJECT`, `CONJURE_LLM_MODEL`, `CONJURE_LLM_REASONING`: Yandex AI Studio. Empty means mock mode. Don't edit these by hand; give `setup.sh` the key and it fills in the rest (URL `https://ai.api.cloud.yandex.net/v1`, folder `b1g3bonfmtl53fs762er`, model `gpt://<folder>/qwen3.6-35b-a3b`, reasoning off: `CONJURE_LLM_REASONING=none`).

### Turning the models on

**Current setup: no key.** The VM has the service account `conjure-models` (role `ai.languageModels.user` on folder `default`) attached, and Conjure signs each model call with the VM's own short-lived IAM token (`CONJURE_LLM_AUTH=yandex-vm`). To (re)apply it on the server:

```bash
cd conjure-ru && git pull && CONJURE_LLM_AUTH=yandex-vm bash scripts/setup.sh
```

**Alternative: an API key**, for a server without an attached service account:

1. In the Yandex Cloud console, folder `default`: create a service account with the `ai.languageModels.user` role, then an API key for it (scope `yc.ai.foundationModels.execute`). Keep the key out of chat, email and this repo.
2. On the server, paste it at the silent prompt:

```bash
ssh conjure-russia
cd conjure-ru && git pull
read -rs CONJURE_LLM_KEY && export CONJURE_LLM_KEY && bash scripts/setup.sh
```

To use another model, add `CONJURE_LLM_MODEL=gpt://b1g3bonfmtl53fs762er/<model>` before `bash`. To list the models the folder can use, run this on the server (it reads the key from the settings file without printing it):

```bash
sudo bash -c 'set -a; . /etc/conjure/env; curl -s -H "Authorization: Api-Key $CONJURE_LLM_KEY" -H "OpenAI-Project: $CONJURE_LLM_PROJECT" https://ai.api.cloud.yandex.net/v1/models'
```

## Cumulus ID

Sign-in needs `https://conjure-ru.infinitumcorporation.ai` on the `conjure` client's allow-list in InfinitumCorp/infinitum-nexus (`packages/cid/src/id-clients.ts`, PR #130) and that change deployed to id.cumuluscloud.app.

Server inventory, costs and the firewall: `infra/yandex-cloud.md` in InfinitumCorp/infinitum-revenue.
