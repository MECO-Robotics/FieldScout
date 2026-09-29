const test = require("node:test");
const assert = require("node:assert/strict");
const core = require("../src/core.js");

function populatedQRScoutDocument(rows) {
  const document = core.createDocument();
  document.rows = rows.map((values, index) => ({
    id: `row-${index}`,
    values: Object.fromEntries(document.columns.map((column, columnIndex) => [column.id, values[columnIndex] || ""]))
  }));
  return document;
}

test("starter sheet exactly matches the 29-field QRScout contract", () => {
  const document = core.createDocument();
  assert.equal(document.columns.length, 29);
  assert.deepEqual(document.columns.map((column) => column.name), core.HEADER_NAMES);
  assert.equal(document.columns[1].role, "matchNumber");
  assert.equal(document.columns[2].role, "teamNumber");
  assert.equal(document.columns[5].role, "autoPoints");
  assert.equal(document.columns[9].role, "autoPoints");
  assert.equal(document.columns[10].role, "teleopPoints");
  assert.equal(document.columns[15].role, "endgamePoints");
  assert.deepEqual(document.columns.slice(16, 19).map((column) => column.role), ["breakdown", "breakdown", "breakdown"]);
  assert.equal(document.columns[24].role, "defenseRating");
});

test("scanner preserves empty first and last QRScout fields", () => {
  const fields = Array.from({ length: 29 }, (_value, index) => String(index));
  fields[0] = "";
  fields[28] = "";
  const result = core.ingestScan(core.createDocument(), fields.join("\t"));
  assert.equal(result.accepted, true);
  assert.equal(result.document.rows.length, 1);
  assert.equal(result.document.rows[0].values["qr-0"], "");
  assert.equal(result.document.rows[0].values["qr-1"], "1");
  assert.equal(result.document.rows[0].values["qr-28"], "");
});

test("duplicate scans are ignored without adding another row", () => {
  const payload = Array.from({ length: 29 }, (_value, index) => String(index)).join("\t");
  const first = core.ingestScan(core.createDocument(), payload);
  const second = core.ingestScan(first.document, payload);
  assert.equal(first.accepted, true);
  assert.equal(second.accepted, false);
  assert.equal(second.document.rows.length, 1);
});

test("2026 QRScout scoring and breakdown fields produce matching analytics", () => {
  const values = Array(29).fill("");
  values[1] = "12";
  values[2] = "8324";
  values[5] = "10";
  values[9] = "C";
  values[10] = "20";
  values[15] = "L2";
  values[17] = "true";
  values[24] = "5";
  const teams = core.analyze(populatedQRScoutDocument([values]));
  assert.equal(teams.length, 1);
  assert.equal(teams[0].teamNumber, 8324);
  assert.equal(teams[0].averageAuto, 25);
  assert.equal(teams[0].averageTeleop, 20);
  assert.equal(teams[0].averageEndgame, 20);
  assert.equal(teams[0].averageOffense, 65);
  assert.equal(teams[0].projectedEPA, 65);
  assert.equal(teams[0].breakdownRate, 1);
  assert.equal(teams[0].averageDefense, 5);
});

test("CSV import and export preserve quoted commas and multiline comments", () => {
  const csv = `${core.HEADER_NAMES.map((value) => `"${value}"`).join(",")}\nAJ,12,8324,,,,,,,,,,,,,,,,,,,,,,,,,,"fast, stable\nsecond line"\n`;
  const document = core.importCSV(csv, "event");
  assert.equal(document.rows.length, 1);
  assert.equal(document.rows[0].values["qr-28"], "fast, stable\nsecond line");
  const exported = core.exportCSV(document);
  const reimported = core.importCSV(exported, "event");
  assert.equal(reimported.rows[0].values["qr-28"], "fast, stable\nsecond line");
});

test("offline analyst compares teams without network access", () => {
  const teams = [
    { teamNumber: 8324, matches: 2, projectedEPA: 60, averageOffense: 63, averageDefense: 4, breakdownRate: 0 },
    { teamNumber: 1234, matches: 2, projectedEPA: 48, averageOffense: 50, averageDefense: 5, breakdownRate: 0.5 }
  ];
  const answer = core.answer("Compare 8324 and 1234", teams);
  assert.match(answer, /Team 8324 leads projected EPA/);
  assert.match(answer, /Team 1234 has the higher defense rating/);
});
