# conjure-ru: Conjure Russia

The Russia version of Conjure™: its own server on Yandex Cloud at **https://conjure-ru.infinitumcorporation.ai** (VM `conjure-russia`, zone ru-central1-a, static IP).

The application code stays in [InfinitumCorp/Conjure](https://github.com/InfinitumCorp/Conjure) and is pinned here by commit. This repo holds what is different for Russia.

## What is different from the main deployment

| | Russia |
|---|---|
| Hosting | Yandex Cloud, nginx + Let's Encrypt in front of Node on 127.0.0.1 |
| Model provider | **100% in Russia, no Claude.** Predictions and code generation run on open-weight models on **Yandex Cloud AI Studio** (default Qwen3.6 35B, Apache 2.0, 256k context; AI Studio withdrew gpt-oss on 2026-10-30), in Russian data centers. `setup.sh` refuses to run if `ANTHROPIC_API_KEY` is set or a model URL points outside Russia, and removes any Cloudflare gateway settings. AI Studio bills per token to the Yandex account (see its [pricing page](https://aistudio.yandex.ru/docs/en/ai-studio/pricing.html)); the account's 4,000 ₽ starter grant covers it at first. With no `CONJURE_LLM_KEY` it runs on the mock provider |
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
- `CONJURE_LLM_URL`, `CONJURE_LLM_KEY`, `CONJURE_LLM_PROJECT`, `CONJURE_LLM_MODEL`, `CONJURE_LLM_REASONING`: Yandex AI Studio. Empty means mock mode. Don't edit these by hand; give `setup.sh` the key and it fills in the rest (URL `https://ai.api.cloud.yandex.net/v1`, folder `b1g3bonfmtl53fs762er`, model `gpt://<folder>/qwen3.6-35b-a3b`, no reasoning setting).

### Turning the models on

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
