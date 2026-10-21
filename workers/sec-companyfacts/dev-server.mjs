/* Local static server that mounts the companyfacts Worker on the same-origin path.
   Listens on 127.0.0.1 only. Not a production host. */
import { createServer } from "node:http";
import { createReadStream, existsSync, statSync } from "node:fs";
import { extname, join, normalize, sep } from "node:path";
import { handle } from "./worker.js";

const root = join(import.meta.dirname, "..", "..");
const port = Number(process.env.PORT || 8765);
const cacheStore = new Map();
const cache = {
  async match(request) {
    const hit = cacheStore.get(request.url);
    return hit ? hit.clone() : undefined;
  },
  async put(request, response) {
    cacheStore.set(request.url, response.clone());
  },
};
const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
};

function safePath(urlPath) {
  let decoded = urlPath.split("?")[0];
  try {
    decoded = decodeURIComponent(decoded);
  } catch (error) {
    return null;
  }
  const rel = decoded.replace(/^\/+/, "");
  if (!rel || rel.split("/").includes("..") || rel.split("/").includes(".git")) return null;
  const full = normalize(join(root, rel));
  const rootPrefix = root.endsWith(sep) ? root : root + sep;
  if (full !== root && !full.startsWith(rootPrefix)) return null;
  return full;
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url || "/", "http://127.0.0.1");
  if (req.method === "GET" && /^\/(?:apps\/financial-sankey\/)?companyfacts\/CIK\d{10}\.json$/.test(url.pathname)) {
    const upstream = await handle(new Request("http://127.0.0.1" + url.pathname, {
      headers: {
        Origin: "http://127.0.0.1:" + port,
        "CF-Connecting-IP": req.socket.remoteAddress || "127.0.0.1",
        Accept: req.headers.accept || "application/json",
      },
    }), { SEC_CONTACT: process.env.SEC_CONTACT || "", CACHE: cache });
    const headers = {};
    upstream.headers.forEach((value, key) => {
      headers[key] = value;
    });
    res.writeHead(upstream.status, headers);
    res.end(Buffer.from(await upstream.arrayBuffer()));
    return;
  }
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.writeHead(405).end();
    return;
  }
  let file = safePath(url.pathname);
  if (!file) {
    res.writeHead(403).end();
    return;
  }
  if (existsSync(file) && statSync(file).isDirectory()) file = join(file, "index.html");
  if (!existsSync(file) || !statSync(file).isFile()) {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("not found");
    return;
  }
  res.writeHead(200, { "Content-Type": types[extname(file)] || "application/octet-stream" });
  if (req.method === "HEAD") {
    res.end();
    return;
  }
  createReadStream(file).pipe(res);
});

server.listen(port, "127.0.0.1", () => {
  console.log("http://127.0.0.1:" + port + "/apps/financial-sankey/?ticker=AAPL");
});
