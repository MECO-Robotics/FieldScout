const test = require("node:test");
const assert = require("node:assert/strict");
const core = require("../src/core.js");
const packageConfig = require("../package.json");

function populatedQRScoutDocument(rows) {
  const document = core.createDocument();
  document.rows = rows.map((values, index) => ({
    id: `row-${index}`,
    values: Object.fromEntries(document.columns.map((column, columnIndex) => [column.id, values[columnIndex] || ""]))
  }));
  return document;
}

test("Windows installer is configured for GitHub auto-updates", () => {
  assert.equal(packageConfig.dependencies["electron-updater"], "^6.8.9");
  assert.deepEqual(packageConfig.build.publish, {
    provider: "github",
    owner: "MECO-Robotics",
    repo: "FieldScout"
  });
  assert.equal(packageConfig.build.nsis.oneClick, false);
});

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
  assert.equal(result.document.rows.length, 2);
  assert.equal(result.document.rows[0].values["qr-0"], "");
  assert.equal(result.document.rows[0].values["qr-1"], "1");
  assert.equal(result.document.rows[0].values["qr-28"], "");
  assert.equal(Object.values(result.document.rows[1].values).every((value) => value === ""), true);
});

test("scanner normalizes printable tab aliases", () => {
  const fields = Array.from({ length: 29 }, (_value, index) => String(index));
  const result = core.ingestScan(core.createDocument(), fields.join("<TAB>"));
  assert.equal(result.accepted, true);
  assert.equal(result.document.rows[0].values["qr-1"], "1");
  assert.equal(result.document.rows[0].values["qr-28"], "28");
});

test("barcode scanned into one sheet cell is distributed across the row", () => {
  const document = core.createDocument();
  const sourceRow = document.rows[0];
  sourceRow.values["qr-0"] = Array.from({ length: 29 }, (_value, index) => String(index)).join("\\t");

  const result = core.ingestScanFromCell(document, sourceRow.id, "qr-0");

  assert.equal(result.handled, true);
  assert.equal(result.accepted, true);
  assert.equal(result.document.rows.length, 2);
  assert.equal(result.document.rows[0].values["qr-1"], "1");
  assert.equal(result.document.rows[0].values["qr-2"], "2");
  assert.equal(result.document.rows[0].values["qr-0"], "0");
});

test("duplicate scans are ignored without adding another row", () => {
  const payload = Array.from({ length: 29 }, (_value, index) => String(index)).join("\t");
  const first = core.ingestScan(core.createDocument(), payload);
  const second = core.ingestScan(first.document, payload);
  assert.equal(first.accepted, true);
  assert.equal(second.accepted, false);
  assert.equal(second.document.rows.length, 2);
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

test("starting position codes expand to scout-facing names and leave a new row", () => {
  const fields = Array(29).fill("");
  fields[0] = "AJ";
  fields[1] = "8";
  fields[2] = "8324";
  fields[3] = "DBFT";
  fields[6] = "1,3";
  fields[21] = "1,6";

  const result = core.ingestScan(core.createDocument(), fields.join("\t"));

  assert.equal(result.document.rows[0].values["qr-3"], "Depot Bump — Trench");
  assert.equal(result.document.rows[0].values["qr-6"], "Outpost, Neutral Zone");
  assert.equal(result.document.rows[0].values["qr-21"], "Outpost Trench, Depot Trench");
  assert.equal(result.document.rows.length, 2);
  assert.equal(Object.values(result.document.rows[1].values).every((value) => value === ""), true);
});

test("saved numeric locations migrate and regain a trailing scanner row", () => {
  const document = core.createDocument();
  document.rows = [{
    id: "saved",
    values: {
      "qr-0": "AJ",
      "qr-3": "OT",
      "qr-6": "2,4",
      "qr-21": "3,5"
    }
  }];

  const migrated = core.normalizeDocument(document);

  assert.equal(migrated.rows.length, 2);
  assert.equal(migrated.rows[0].values["qr-3"], "Outpost Trench");
  assert.equal(migrated.rows[0].values["qr-6"], "Depot, Neutral Zone — 2nd Pass");
  assert.equal(migrated.rows[0].values["qr-21"], "Hub, Depot");
  assert.equal(Object.values(migrated.rows[1].values).every((value) => value === ""), true);
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

test("CSV export omits the automatic blank scanner row", () => {
  const document = core.createDocument();
  document.rows = [
    { id: "filled", values: { "qr-0": "AJ" } },
    core.blankRow(document.columns)
  ];
  assert.equal(core.parseCSV(core.exportCSV(document)).length, 2);
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

test("same team and match produces a reviewable conflict", () => {
  const firstFields = Array(29).fill("");
  firstFields[0] = "AJ";
  firstFields[1] = "7";
  firstFields[2] = "8324";
  firstFields[24] = "3";
  const secondFields = [...firstFields];
  secondFields[24] = "5";

  const first = core.ingestScan(core.createDocument(), firstFields.join("\t"));
  const conflict = core.ingestScan(first.document, secondFields.join("\t"));
  assert.equal(conflict.accepted, false);
  assert.equal(conflict.conflict.teamNumber, 8324);
  assert.equal(conflict.conflict.matchNumber, 7);
  assert.deepEqual(conflict.conflict.differences.find((difference) => difference.columnName === "Defense Skill"), {
    columnName: "Defense Skill",
    previousValue: "3",
    scannedValue: "5"
  });
  assert.equal(conflict.document.rows.length, 2);

  const replaced = core.ingestScan(first.document, secondFields.join("\t"), "replace");
  assert.equal(replaced.accepted, true);
  assert.equal(replaced.document.rows.length, 2);
  assert.equal(replaced.document.rows[0].values["qr-24"], "5");
});

test("data quality reports duplicates, invalid ratings, and six-team match coverage", () => {
  const a = Array(29).fill("");
  a[0] = "AJ";
  a[1] = "9";
  a[2] = "8324";
  a[24] = "7";
  const b = [...a];
  b[0] = "MK";
  const summary = core.dataQuality(populatedQRScoutDocument([a, b]));
  assert.equal(summary.entryCount, 2);
  assert.equal(summary.rowsNeedingAttention, 2);
  assert.equal(summary.matches[0].teamNumbers.length, 1);
  assert.equal(summary.matches[0].missingScoutCount, 5);
  assert.ok(summary.issues.some((issue) => issue.message.includes("between 0 and 5")));
  assert.ok(summary.issues.some((issue) => issue.message.includes("2 entries")));
});
