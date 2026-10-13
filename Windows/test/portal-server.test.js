const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const core = require("../src/core.js");
const {
  createPortalPayload,
  startPortalServer,
  validatePortalSubmission
} = require("../portal-server.js");

function sampleFields() {
  const fields = Object.fromEntries(core.QRSCOUT_FIELD_IDENTIFIERS.map((identifier, index) => [identifier, `field-${index}`]));
  fields.si = "AJ";
  fields.mn = "12";
  fields.tn = "8324";
  fields.sp = "Outpost Trench";
  fields.ns = "false";
  fields.ast = "true";
  fields.ecl = "L3";
  return fields;
}

test("iPad Portal validates and creates the exact QRSCOUT2 contract", () => {
  const submission = validatePortalSubmission({ submissionId: "entry-1", fields: sampleFields() });
  const payload = createPortalPayload(submission.fields);
  const result = core.ingestScan(core.createDocument(), payload);

  assert.match(payload, /^QRSCOUT2-/);
  assert.equal(result.accepted, true);
  assert.equal(result.document.rows.length, 2);
  assert.equal(result.document.rows[0].values["qr-0"], "AJ");
  assert.equal(result.document.rows[0].values["qr-1"], "12");
  assert.equal(result.document.rows[0].values["qr-2"], "8324");
  assert.equal(result.document.rows[0].values["qr-3"], "Outpost Trench");
  assert.equal(result.document.rows[0].values["qr-15"], "L3");
});

test("iPad Portal rejects missing fields instead of shifting columns", () => {
  const fields = sampleFields();
  delete fields.afs;
  assert.throws(
    () => validatePortalSubmission({ submissionId: "entry-2", fields }),
    /exact 29 QRScout fields/
  );
});

test("offline iPad page submits one entry through the local HTTP server", async (t) => {
  let document = core.createDocument();
  let submissionCount = 0;
  const started = await startPortalServer({
    pagePath: path.join(__dirname, "..", "..", "Shared", "ScoutingPortal.html"),
    port: 0,
    onSubmission: async (payload) => {
      submissionCount += 1;
      const result = core.ingestScan(document, payload);
      document = result.document;
      return { statusCode: 200, status: result.accepted ? "accepted" : "duplicate", message: result.message };
    }
  });
  t.after(() => new Promise((resolve) => started.server.close(resolve)));
  const base = `http://127.0.0.1:${started.port}`;

  const health = await fetch(`${base}/health`);
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), { status: "ready" });

  const page = await fetch(base);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /No app or internet needed/);

  const response = await fetch(`${base}/api/entries`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-FieldScout-Portal": "1",
      Origin: base
    },
    body: JSON.stringify({ submissionId: "entry-3", fields: sampleFields() })
  });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).status, "accepted");
  assert.equal(submissionCount, 1);
  assert.equal(document.rows.length, 2);
  assert.equal(document.rows[0].values["qr-2"], "8324");
});

test("local HTTP server rejects cross-origin portal submissions", async (t) => {
  const started = await startPortalServer({
    pagePath: path.join(__dirname, "..", "..", "Shared", "ScoutingPortal.html"),
    port: 0,
    onSubmission: async () => ({ statusCode: 200, status: "accepted", message: "added" })
  });
  t.after(() => new Promise((resolve) => started.server.close(resolve)));
  const base = `http://127.0.0.1:${started.port}`;
  const response = await fetch(`${base}/api/entries`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-FieldScout-Portal": "1",
      Origin: "https://example.com"
    },
    body: JSON.stringify({ submissionId: "entry-4", fields: sampleFields() })
  });
  assert.equal(response.status, 403);
});
