// Forwards conjure.infinitumcorporation.ai to Conjure Russia (conjure-ru.infinitumcorporation.ai)
// over HTTPS, so networks that block Yandex Cloud can still reach it. Requests and responses pass
// through unchanged, apart from the few headers that name the host.

export const UPSTREAM = "conjure-ru.infinitumcorporation.ai";

/** Rewrites one request for the Russian server. */
export function toUpstream(request: Request): Request {
  const url = new URL(request.url);
  const front = url.host;
  const target = new URL(url.pathname + url.search, `https://${UPSTREAM}`);
  const headers = new Headers(request.headers);
  headers.delete("host");
  // Conjure refuses cross-site POSTs by comparing Origin with Host. A browser on the front sends
  // the front's origin; tell the server it's its own, since the two hostnames are the same app.
  if (headers.get("origin") === `https://${front}`) headers.set("origin", `https://${UPSTREAM}`);
  headers.set("x-forwarded-host", front);
  headers.set("x-forwarded-proto", "https");
  return new Request(target, {
    method: request.method,
    headers,
    body: request.method === "GET" || request.method === "HEAD" ? undefined : request.body,
    redirect: "manual",
    // Streams the body through; required by the Fetch spec (and Node) when the body is a stream.
    duplex: "half",
  } as RequestInit);
}

/** Keeps redirects to the server's own pages on the front's hostname. */
export function fromUpstream(response: Response, front: string): Response {
  const location = response.headers.get("location");
  if (!location?.startsWith(`https://${UPSTREAM}`)) return response;
  const out = new Response(response.body, response);
  out.headers.set("location", `https://${front}${location.slice(`https://${UPSTREAM}`.length)}`);
  return out;
}

export default {
  async fetch(request: Request): Promise<Response> {
    const front = new URL(request.url).host;
    try {
      return fromUpstream(await fetch(toUpstream(request)), front);
    } catch {
      return new Response(JSON.stringify({ error: "Conjure is unreachable right now; try again shortly" }), {
        status: 502,
        headers: { "content-type": "application/json", "cache-control": "no-store" },
      });
    }
  },
};
