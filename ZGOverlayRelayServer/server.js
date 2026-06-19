const http = require("http");

const port = Number(process.env.PORT || 8080);
const maxBodyBytes = Number(process.env.MAX_BODY_BYTES || 2_500_000);
const streams = new Map();

function send(res, status, body, headers = {}) {
  res.writeHead(status, {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Cache-Control",
    "Cache-Control": "no-store",
    ...headers,
  });
  res.end(body);
}

function readBody(req, callback) {
  const chunks = [];
  let size = 0;

  req.on("data", (chunk) => {
    size += chunk.length;
    if (size > maxBodyBytes) {
      req.destroy();
      return;
    }
    chunks.push(chunk);
  });

  req.on("end", () => callback(null, Buffer.concat(chunks)));
  req.on("error", (error) => callback(error));
}

function streamFor(key) {
  if (!streams.has(key)) {
    streams.set(key, { state: null, frame: null, updatedAt: 0 });
  }
  return streams.get(key);
}

const server = http.createServer((req, res) => {
  if (req.method === "OPTIONS") {
    send(res, 204, "");
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const parts = url.pathname.split("/").filter(Boolean);

  if (req.method === "GET" && url.pathname === "/health") {
    send(res, 200, JSON.stringify({ ok: true, streams: streams.size }), {
      "Content-Type": "application/json",
    });
    return;
  }

  if (parts.length === 3 && parts[0] === "push" && req.method === "POST") {
    const key = parts[1];
    const kind = parts[2];
    if (kind !== "state" && kind !== "frame") {
      send(res, 404, "unknown push kind");
      return;
    }

    readBody(req, (error, body) => {
      if (error || !body || body.length === 0) {
        send(res, 400, "empty body");
        return;
      }

      const stream = streamFor(key);
      stream[kind] = body;
      stream.updatedAt = Date.now();
      send(res, 200, JSON.stringify({ ok: true, key, kind, bytes: body.length }), {
        "Content-Type": "application/json",
      });
    });
    return;
  }

  if (parts.length === 3 && parts[0] === "latest" && req.method === "GET") {
    const key = parts[1];
    const kind = parts[2];
    const stream = streams.get(key);
    if (!stream || !stream[kind]) {
      send(res, 404, "not ready");
      return;
    }

    send(res, 200, stream[kind], {
      "Content-Type": kind === "frame" ? "image/jpeg" : "application/json",
      "X-ZG-Updated-At": String(stream.updatedAt),
    });
    return;
  }

  send(res, 404, "not found");
});

server.listen(port, () => {
  console.log(`ZG overlay relay listening on ${port}`);
});
