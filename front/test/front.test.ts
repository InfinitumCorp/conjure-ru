// The front rewrites only what names the host; everything else passes through.
import { test } from "node:test";
import assert from "node:assert/strict";
import { toUpstream, fromUpstream, UPSTREAM } from "../src/index.ts";

const FRONT = "conjure.infinitumcorporation.ai";

test("requests go to the Russian server with path, query, method and body intact", async () => {
  const r = toUpstream(new Request(`https://${FRONT}/api/predict?x=1`, { method: "POST", headers: { authorization: "Bearer k", "content-type": "application/json" }, body: '{"q":1}' }));
  assert.equal(r.url, `https://${UPSTREAM}/api/predict?x=1`);
  assert.equal(r.method, "POST");
  assert.equal(r.headers.get("authorization"), "Bearer k");
  assert.equal(r.headers.get("x-forwarded-host"), FRONT);
  assert.equal(await r.text(), '{"q":1}');
  assert.equal(r.redirect, "manual");
});

test("a browser's own-origin header is mapped to the server's, a foreign one is left alone", () => {
  const own = toUpstream(new Request(`https://${FRONT}/api/x`, { method: "POST", headers: { origin: `https://${FRONT}` }, body: "{}" }));
  assert.equal(own.headers.get("origin"), `https://${UPSTREAM}`);
  const foreign = toUpstream(new Request(`https://${FRONT}/api/x`, { method: "POST", headers: { origin: "https://evil.example" }, body: "{}" }));
  assert.equal(foreign.headers.get("origin"), "https://evil.example");
});

test("redirects to the server's own pages stay on the front; others are untouched", () => {
  const own = fromUpstream(new Response(null, { status: 303, headers: { location: `https://${UPSTREAM}/login` } }), FRONT);
  assert.equal(own.headers.get("location"), `https://${FRONT}/login`);
  const rel = fromUpstream(new Response(null, { status: 303, headers: { location: "/login" } }), FRONT);
  assert.equal(rel.headers.get("location"), "/login");
  const sso = fromUpstream(new Response(null, { status: 302, headers: { location: "https://id.cumuluscloud.app/authorize" } }), FRONT);
  assert.equal(sso.headers.get("location"), "https://id.cumuluscloud.app/authorize");
});
