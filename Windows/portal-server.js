"use strict";

const fs = require("node:fs/promises");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const core = require("./src/core.js");

const DEFAULT_PORT = 8324;
const MAX_BODY_BYTES = 64 * 1024;

function createPortalPayload(fields) {
  const normalized = Object.fromEntries(core.QRSCOUT_FIELD_IDENTIFIERS.map((identifier) => [identifier, String(fields[identifier] ?? "")]));
  return `QRSCOUT2-${Buffer.from(JSON.stringify({ v: 2, fields: normalized }), "utf8").toString("base64url")}`;
}

function validatePortalSubmission(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("The scouting entry is not valid JSON.");
  const submissionId = String(value.submissionId || "");
  if (!submissionId || submissionId.length > 128) throw new Error("The scouting entry is missing its submission ID.");
  if (!value.fields || typeof value.fields !== "object" || Array.isArray(value.fields)) throw new Error("The scouting entry has no fields.");
  const actual = Object.keys(value.fields).sort();
  const expected = [...core.QRSCOUT_FIELD_IDENTIFIERS].sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error("The scouting entry does not contain the exact 29 QRScout fields.");
  const fields = {};
  let totalLength = 0;
  for (const identifier of core.QRSCOUT_FIELD_IDENTIFIERS) {
    if (typeof value.fields[identifier] !== "string") throw new Error(`Field ${identifier} must be text.`);
    const text = value.fields[identifier].replace(/[\r\n\t]/g, " ").trim();
    if (text.length > 2_000) throw new Error(`Field ${identifier} is too long.`);
    totalLength += text.length;
    fields[identifier] = text;
  }
  if (totalLength > 20_000) throw new Error("The scouting entry is too large.");
  if (!/^\d+$/.test(fields.mn) || !/^\d+$/.test(fields.tn)) throw new Error("Match number and team number are required.");
  return { submissionId, fields };
}

function localPortalURLs(port) {
  const addresses = new Set();
  for (const entries of Object.values(os.networkInterfaces())) {
    for (const entry of entries || []) {
      if (entry.family === "IPv4" && !entry.internal && !entry.address.startsWith("169.254.")) {
        addresses.add(`http://${entry.address}:${port}`);
      }
    }
  }
  const hostname = os.hostname();
  if (hostname) addresses.add(`http://${hostname}:${port}`);
  return [...addresses];
}

function writeResponse(response, statusCode, contentType, body) {
  const data = Buffer.isBuffer(body) ? body : Buffer.from(String(body), "utf8");
  response.writeHead(statusCode, {
    "Content-Type": contentType,
    "Content-Length": data.length,
    "Cache-Control": "no-store",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY"
  });
  response.end(data);
}

function writeJSON(response, statusCode, value) {
  writeResponse(response, statusCode, "application/json; charset=utf-8", JSON.stringify(value));
}

async function readJSON(request) {
  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.length;
    if (length > MAX_BODY_BYTES) throw new Error("The scouting entry is too large.");
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function originIsAllowed(request) {
  const origin = request.headers.origin;
  if (!origin) return true;
  return origin === `http://${request.headers.host}`;
}

function createPortalServer({ pagePath, onSubmission }) {
  if (typeof onSubmission !== "function") throw new Error("A portal submission handler is required.");
  return http.createServer(async (request, response) => {
    const requestURL = new URL(request.url || "/", `http://${request.headers.host || "localhost"}`);
    try {
      if (request.method === "GET" && requestURL.pathname === "/health") {
        writeJSON(response, 200, { status: "ready" });
        return;
      }
      if (request.method === "GET" && (requestURL.pathname === "/" || requestURL.pathname === "/index.html")) {
        const page = await fs.readFile(pagePath);
        writeResponse(response, 200, "text/html; charset=utf-8", page);
        return;
      }
      if (request.method === "POST" && requestURL.pathname === "/api/entries") {
        if (request.headers["x-fieldscout-portal"] !== "1" || !originIsAllowed(request)) {
          writeJSON(response, 403, { message: "This submission did not come from the FieldScout iPad Portal." });
          return;
        }
        if (!String(request.headers["content-type"] || "").toLowerCase().startsWith("application/json")) {
          writeJSON(response, 415, { message: "FieldScout only accepts JSON scouting entries." });
          return;
        }
        const submission = validatePortalSubmission(await readJSON(request));
        const result = await onSubmission(createPortalPayload(submission.fields), submission);
        writeJSON(response, result.statusCode || 200, { status: result.status || "accepted", message: result.message || "Scouting entry added." });
        return;
      }
      writeJSON(response, 404, { message: "Not found." });
    } catch (error) {
      writeJSON(response, error instanceof SyntaxError ? 400 : 422, { message: error.message || "The scouting entry could not be processed." });
    }
  });
}

async function startPortalServer({ pagePath, onSubmission, port = DEFAULT_PORT }) {
  const server = createPortalServer({ pagePath: path.resolve(pagePath), onSubmission });
  await new Promise((resolve, reject) => {
    const onError = (error) => { server.off("listening", onListening); reject(error); };
    const onListening = () => { server.off("error", onError); resolve(); };
    server.once("error", onError);
    server.once("listening", onListening);
    server.listen(port, "0.0.0.0");
  });
  const address = server.address();
  const actualPort = typeof address === "object" && address ? address.port : port;
  return { server, port: actualPort, urls: localPortalURLs(actualPort) };
}

module.exports = {
  DEFAULT_PORT,
  MAX_BODY_BYTES,
  createPortalPayload,
  createPortalServer,
  localPortalURLs,
  startPortalServer,
  validatePortalSubmission
};
