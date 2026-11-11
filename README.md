# conjure-ru: Conjure Russia

The Russia version of Conjure™: its own server on Yandex Cloud at **https://conjure-ru.infinitumcorporation.ai** (VM `conjure-russia`, zone ru-central1-a, static IP).

The application code stays in [InfinitumCorp/Conjure](https://github.com/InfinitumCorp/Conjure) and is pinned here by commit. This repo holds what is different for Russia.

## What is different from the main deployment

| | Russia |
|---|---|
| Hosting | Yandex Cloud, nginx + Let's Encrypt in front of Node on 127.0.0.1 |
| Model provider | **No Claude.** `ANTHROPIC_API_KEY` is never set (`setup.sh` refuses to run if it is). Free open-weight models through the conjure-llm gateway: Workers AI Qwen3 within its free daily allowance, then free fallbacks (OVHcloud, Pollinations, LLM7, and Groq/NVIDIA/OpenRouter if keyed). The gateway reaches those providers from Cloudflare, so Russian geo-blocks (Groq returns 403 here) don't apply. With no `CONJURE_LLM_KEY` it runs on the mock provider |
| Sign-in | Required (`CONJURE_ACCESS_TOKEN` set). Staff sign in with Cumulus ID; only IDs in `CID_OWNERS` get in |
| Preview | Separate host `conjure-ru-preview.infinitumcorporation.ai` (127.0.0.1:4318) |
| Backups | Yandex disk snapshot daily at 00:00 UTC, 7 kept |

## Layout

- `scripts/setup.sh`: Node (checksum-verified), the pinned Conjure release in `/opt/conjure/releases/<sha>`, the sandboxed `conjure` systemd service, nginx and TLS. Re-runnable.
- `scripts/check.sh`: outside checks; also runs from the `check` workflow on demand.

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
- `CONJURE_LLM_URL`, `CONJURE_LLM_KEY`, `CONJURE_LLM_ACCESS_ID`, `CONJURE_LLM_ACCESS_SECRET`, `CONJURE_LLM_MODEL`, `CONJURE_LLM_REASONING`: the open-weight gateway. Empty means mock mode. Rather than editing by hand, pass the key and Access service token to `setup.sh` in the environment; it fills in the rest (URL `https://conjure-llm.infinitumcorp.workers.dev/v1`, model `@cf/qwen/qwen3-30b-a3b-fp8`, reasoning `none`). The values live in AWS SSM (us-east-2): `/conjure/llm-key`, `/conjure/llm-access-id`, `/conjure/llm-access-secret`.

## Cumulus ID

Sign-in needs `https://conjure-ru.infinitumcorporation.ai` on the `conjure` client's allow-list in InfinitumCorp/infinitum-nexus (`packages/cid/src/id-clients.ts`, PR #130) and that change deployed to id.cumuluscloud.app.

Server inventory, costs and the firewall: `infra/yandex-cloud.md` in InfinitumCorp/infinitum-revenue.
