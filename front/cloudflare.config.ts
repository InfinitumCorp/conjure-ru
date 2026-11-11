// Global front for Conjure Russia. Deploy: cf deploy (from this folder).
//
// Conjure runs only on the Yandex server in Russia. A few networks outside Russia block Yandex
// Cloud's address range, so this Worker gives Conjure a second, global hostname that forwards every
// request to the Russian server over HTTPS. Nothing runs here but the forwarding.
import { defineConfig } from "cf/config";

import * as entrypoint from "./src/index.ts" with { type: "cf-worker" };

export default defineConfig({
  worker: {
    name: "conjure-front",
    entrypoint,
    compatibilityDate: "2026-10-01",
    domains: ["conjure.infinitumcorporation.ai"],
    // Only the custom domain: no *.workers.dev address.
    workersDev: false,
    previewUrls: false,
    // Run close to the Russian server, so the long leg is Cloudflare's network, not the open internet.
    placement: { mode: "smart" },
  },
});
