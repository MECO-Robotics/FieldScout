(function attachFieldScoutCore(root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.FieldScoutCore = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function buildCore() {
  "use strict";

  const QRSCOUT_FIELDS = [
    ["Scouter Initials", "text", "none"],
    ["Match Number", "integer", "matchNumber"],
    ["Team Number", "integer", "teamNumber"],
    ["Starting Position", "text", "none"],
    ["No Show", "boolean", "none"],
    ["Fuel Scored", "integer", "autoPoints"],
    ["Where collected Fuel", "text", "none"],
    ["Other Auto actions", "text", "none"],
    ["Robot Stuck or a Stop in Auto", "boolean", "none"],
    ["Climbed", "text", "autoPoints"],
    ["Fuel Scored", "integer", "teleopPoints"],
    ["Bump Trench", "text", "none"],
    ["Deffended by Opponent", "boolean", "none"],
    ["Fuel Fed", "integer", "none"],
    ["Opposing Zone Actions", "text", "none"],
    ["Climbed", "text", "endgamePoints"],
    ["Mechanical Issue", "boolean", "breakdown"],
    ["Died", "boolean", "breakdown"],
    ["Triped/Fell Over", "boolean", "breakdown"],
    ["Scoring Efectiveness", "integer", "none"],
    ["Scored How?", "text", "none"],
    ["Scoring Location", "text", "none"],
    ["Feeding/Passing Skill", "integer", "none"],
    ["Passed How?", "text", "none"],
    ["Defense Skill", "integer", "defenseRating"],
    ["Yello/Red Card", "text", "none"],
    ["First Pick", "text", "none"],
    ["Second Pick", "text", "none"],
    ["Comments", "text", "none"]
  ];

  const HEADER_NAMES = QRSCOUT_FIELDS.map((field) => field[0]);
  const SCOUT_FACING_VALUES = {
    startingposition: {
      OT: "Outpost Trench",
      OBFT: "Outpost Bump — Trench",
      OBFH: "Outpost Bump — Hub",
      H: "Hub",
      DBFH: "Depot Bump — Hub",
      DBFT: "Depot Bump — Trench",
      DT: "Depot Trench"
    },
    wherecollectedfuel: {
      1: "Outpost",
      2: "Depot",
      3: "Neutral Zone",
      4: "Neutral Zone — 2nd Pass",
      5: "Did Not Move",
      6: "Moved Without Collecting"
    },
    otherautoactions: { 1: "Passed", 2: "Bump", 3: "Trench" },
    bumptrench: { 1: "Bump", 2: "Trench" },
    opposingzoneactions: { 1: "Collecting", 2: "Defense" },
    scoringlocation: {
      1: "Outpost Trench",
      2: "Outpost",
      3: "Hub",
      4: "Ladder",
      5: "Depot",
      6: "Depot Trench"
    }
  };

  function expandedScoutFacingValue(value, columnName) {
    const values = SCOUT_FACING_VALUES[compactName(columnName)];
    if (!values) return String(value ?? "");
    return String(value ?? "")
      .split(",")
      .map((component) => {
        const original = component.trim();
        return values[original.toUpperCase()] || original;
      })
      .join(", ");
  }

  function id(prefix = "id") {
    if (globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") {
      return globalThis.crypto.randomUUID();
    }
    return `${prefix}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  }

  function qrScoutColumns() {
    return QRSCOUT_FIELDS.map(([name, type, role], index) => ({
      id: `qr-${index}`,
      name,
      type,
      role
    }));
  }

  function blankRow(columns) {
    return { id: id("row"), values: Object.fromEntries(columns.map((column) => [column.id, ""])) };
  }

  function createDocument() {
    const columns = qrScoutColumns();
    return {
      version: 1,
      title: "MECO QRScout 2026",
      columns,
      rows: [blankRow(columns)],
      ingestedScanPayloads: [],
      teamAnnotations: [],
      updatedAt: new Date().toISOString()
    };
  }

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function normalizeDocument(input) {
    if (!input || !Array.isArray(input.columns) || !Array.isArray(input.rows)) return createDocument();
    const document = clone(input);
    document.version = 1;
    document.title = document.title || "FieldScout";
    document.ingestedScanPayloads = Array.isArray(document.ingestedScanPayloads)
      ? document.ingestedScanPayloads
      : [];
    document.teamAnnotations = Array.isArray(document.teamAnnotations)
      ? document.teamAnnotations
      : [];
    document.columns = document.columns.map((column, index) => ({
      id: column.id || id(`column-${index}`),
      name: column.name || `Column ${index + 1}`,
      type: column.type || "text",
      role: column.role || "none"
    }));
    document.rows = document.rows.map((row) => ({ id: row.id || id("row"), values: row.values || {} }));
    for (const column of document.columns) {
      if (!SCOUT_FACING_VALUES[compactName(column.name)]) continue;
      document.rows.forEach((row) => {
        row.values[column.id] = expandedScoutFacingValue(row.values[column.id], column.name);
      });
    }
    document.rows = document.rows.filter((row) => (
      Object.values(row.values).some((value) => String(value).trim())
    ));
    document.rows.push(blankRow(document.columns));
    return document;
  }

  function isExactQRScoutHeader(names) {
    return names.length === HEADER_NAMES.length && names.every((name, index) => name === HEADER_NAMES[index]);
  }

  function parseCSV(text) {
    const rows = [];
    let row = [];
    let field = "";
    let inQuotes = false;
    for (let index = 0; index < text.length; index += 1) {
      const character = text[index];
      if (inQuotes) {
        if (character === '"' && text[index + 1] === '"') {
          field += '"';
          index += 1;
        } else if (character === '"') {
          inQuotes = false;
        } else {
          field += character;
        }
      } else if (character === '"') {
        inQuotes = true;
      } else if (character === ",") {
        row.push(field);
        field = "";
      } else if (character === "\n") {
        row.push(field.replace(/\r$/, ""));
        rows.push(row);
        row = [];
        field = "";
      } else {
        field += character;
      }
    }
    if (field.length > 0 || row.length > 0) {
      row.push(field.replace(/\r$/, ""));
      rows.push(row);
    }
    return rows;
  }

  function escapeCSV(value) {
    const text = String(value ?? "");
    if (!/[",\n]/.test(text)) return text;
    return `"${text.replaceAll('"', '""')}"`;
  }

  function exportCSV(document) {
    const lines = [document.columns.map((column) => escapeCSV(column.name)).join(",")];
    const meaningful = document.rows.filter((row) => (
      Object.values(row.values).some((value) => String(value).trim())
    ));
    for (const row of meaningful) {
      lines.push(document.columns.map((column) => escapeCSV(row.values[column.id] || "")).join(","));
    }
    return `${lines.join("\n")}\n`;
  }

  function compactName(name) {
    return String(name).toLowerCase().replace(/[^a-z]/g, "");
  }

  function inferRole(name) {
    const key = compactName(name);
    if (["team", "teamnumber", "teamnum", "frcteam"].includes(key)) return "teamNumber";
    if (["match", "matchnumber", "matchnum", "qual", "qualification"].includes(key)) return "matchNumber";
    if (key.includes("break") || key.includes("broke") || key.includes("disabled") || key === "died") return "breakdown";
    if (key.includes("defense") || key.includes("defence")) return "defenseRating";
    if (key.includes("penalty") || key.includes("foulpoint")) return "penaltyPoints";
    if (key.includes("endgame") || key.includes("climbpoint")) return "endgamePoints";
    if (key.includes("teleop") || key.includes("tele")) return "teleopPoints";
    if (key.includes("auto") || key.includes("auton")) return "autoPoints";
    return "none";
  }

  function inferType(name, values) {
    const nonempty = values.map((value) => String(value).trim()).filter(Boolean);
    if (nonempty.length === 0) return "text";
    const booleans = new Set(["true", "false", "yes", "no", "y", "n", "0", "1", "x"]);
    if (nonempty.every((value) => booleans.has(value.toLowerCase()))) return "boolean";
    if (nonempty.every((value) => /^-?\d+$/.test(value))) return "integer";
    if (nonempty.every((value) => Number.isFinite(Number(value)))) return "decimal";
    return "text";
  }

  function importCSV(text, title = "Imported Scouting") {
    const records = parseCSV(text);
    if (!records.length || !records[0].length) throw new Error("The CSV file has no header row.");
    const header = records[0];
    const columns = isExactQRScoutHeader(header)
      ? qrScoutColumns()
      : header.map((name, index) => ({
          id: id(`column-${index}`),
          name: name || `Column ${index + 1}`,
          type: inferType(name, records.slice(1).map((record) => record[index] || "")),
          role: inferRole(name)
        }));
    const rows = records.slice(1)
      .filter((record) => record.some((value) => String(value).trim()))
      .map((record) => ({
        id: id("row"),
        values: Object.fromEntries(columns.map((column, index) => [column.id, record[index] || ""]))
      }));
    return {
      version: 1,
      title,
      columns,
      rows,
      ingestedScanPayloads: [],
      teamAnnotations: [],
      updatedAt: new Date().toISOString()
    };
  }

  function trimScannerEnvelope(raw) {
    return String(raw ?? "").replace(/^[ \r\n]+|[ \r\n]+$/g, "");
  }

  function normalizeScannerPayload(raw) {
    let payload = trimScannerEnvelope(raw);
    if (!payload || payload.trimStart().startsWith("{")) return payload;
    return payload
      .replace(/\\t/g, "\t")
      .replace(/<tab>/gi, "\t")
      .replace(/[⇥\v\u001d\u001e\u001f]/g, "\t");
  }

  function parseScan(raw) {
    const preserved = normalizeScannerPayload(raw);
    if (!preserved) throw new Error("Scan a barcode before adding it.");

    if (preserved.trimStart().startsWith("{")) {
      const object = JSON.parse(preserved);
      if (!object || Array.isArray(object) || typeof object !== "object") throw new Error("The JSON scan must be an object.");
      return { kind: "named", entries: Object.entries(object).map(([key, value]) => [key, String(value ?? "")]) };
    }

    if (preserved.includes("\t")) {
      const fields = preserved.split("\t");
      if (fields.length === QRSCOUT_FIELDS.length) return { kind: "qrScout", fields };
      return { kind: "positional", fields };
    }

    if (preserved.includes("=")) {
      const pairs = preserved.split(/[;\n]/).map((part) => part.trim()).filter(Boolean);
      const entries = pairs.map((pair) => {
        const split = pair.indexOf("=");
        if (split < 1) throw new Error(`Invalid named field: ${pair}`);
        return [pair.slice(0, split).trim(), pair.slice(split + 1).trim()];
      });
      return { kind: "named", entries };
    }

    const records = parseCSV(preserved);
    if (records.length === 1 && records[0].length > 1) return { kind: "positional", fields: records[0] };
    throw new Error("This barcode is not JSON, key=value, CSV, or tab-separated data.");
  }

  function isPackedScan(raw) {
    try {
      const parsed = parseScan(raw);
      if (parsed.kind === "qrScout") return true;
      if (parsed.kind === "positional") return parsed.fields.length >= 8;
      return parsed.entries.length >= 2;
    } catch (_error) {
      return false;
    }
  }

  function meaningfulRows(document) {
    return document.rows.filter((row) => Object.values(row.values).some((value) => String(value).trim()));
  }

  function ingestScan(inputDocument, raw, conflictResolution = "ask") {
    let document = normalizeDocument(inputDocument);
    const exactRaw = normalizeScannerPayload(raw);
    if (document.ingestedScanPayloads.includes(exactRaw)) {
      return { accepted: false, document, message: "Duplicate scan ignored." };
    }
    const parsed = parseScan(exactRaw);
    let values = {};

    if (parsed.kind === "qrScout") {
      if (!isExactQRScoutHeader(document.columns.map((column) => column.name)) && meaningfulRows(document).length === 0) {
        document.columns = qrScoutColumns();
        document.rows = [];
      }
      if (!isExactQRScoutHeader(document.columns.map((column) => column.name))) {
        const qrColumns = qrScoutColumns();
        const existingIds = new Set(document.columns.map((column) => column.id));
        for (const column of qrColumns) {
          if (!existingIds.has(column.id)) document.columns.push(column);
        }
      }
      values = Object.fromEntries(qrScoutColumns().map((column, index) => [column.id, parsed.fields[index] || ""]));
      for (const index of [3, 6, 7, 11, 14, 21]) {
        values[`qr-${index}`] = expandedScoutFacingValue(values[`qr-${index}`], HEADER_NAMES[index]);
      }
    } else if (parsed.kind === "named") {
      const columnsByName = new Map(document.columns.map((column) => [compactName(column.name), column]));
      for (const [name, value] of parsed.entries) {
        const key = compactName(name);
        let column = columnsByName.get(key);
        if (!column) {
          column = { id: id("column"), name, type: "text", role: inferRole(name) };
          document.columns.push(column);
          columnsByName.set(key, column);
        }
        values[column.id] = expandedScoutFacingValue(value, name);
      }
    } else {
      while (document.columns.length < parsed.fields.length) {
        document.columns.push({
          id: id("column"),
          name: `Scanned Field ${document.columns.length + 1}`,
          type: "text",
          role: "none"
        });
      }
      values = Object.fromEntries(document.columns.slice(0, parsed.fields.length).map((column, index) => [column.id, parsed.fields[index] || ""]));
    }

    const teamColumn = document.columns.find((column) => column.role === "teamNumber");
    const matchColumn = document.columns.find((column) => column.role === "matchNumber");
    const team = teamColumn ? Number.parseInt(String(values[teamColumn.id] ?? "").trim(), 10) : 0;
    const match = matchColumn ? Number.parseInt(String(values[matchColumn.id] ?? "").trim(), 10) : 0;
    const existing = team > 0 && match > 0
      ? document.rows.find((row) => Number.parseInt(row.values[teamColumn.id] || "0", 10) === team && Number.parseInt(row.values[matchColumn.id] || "0", 10) === match)
      : null;

    if (existing) {
      const differences = document.columns.flatMap((column) => {
        const previousValue = existing.values[column.id] || "";
        const scannedValue = values[column.id] || "";
        return previousValue === scannedValue ? [] : [{ columnName: column.name, previousValue, scannedValue }];
      });
      if (!differences.length) {
        return { accepted: false, document, message: `Duplicate ignored — team ${team}, match ${match} already has the same values.` };
      }
      if (conflictResolution === "ask") {
        return {
          accepted: false,
          document,
          message: `Conflict found for team ${team}, match ${match}.`,
          conflict: { existingRowId: existing.id, teamNumber: team, matchNumber: match, differences, rawPayload: exactRaw }
        };
      }
      if (conflictResolution === "replace") {
        existing.values = values;
      } else if (conflictResolution === "keep") {
        document.rows.push({ id: id("row"), values });
      } else {
        throw new Error("Unknown scan conflict resolution.");
      }
    } else {
      document.rows = document.rows.filter((row) => Object.values(row.values).some((value) => String(value).trim()));
      document.rows.push({ id: id("row"), values });
    }
    document.rows = document.rows.filter((row) => Object.values(row.values).some((value) => String(value).trim()));
    document.rows.push(blankRow(document.columns));
    document.ingestedScanPayloads.push(exactRaw);
    document.updatedAt = new Date().toISOString();
    return {
      accepted: true,
      document,
      message: existing && conflictResolution === "replace"
        ? `Team ${team}, match ${match} was replaced with the new scan.`
        : existing && conflictResolution === "keep"
          ? `Both entries were kept for team ${team}, match ${match}.`
          : parsed.kind === "qrScout"
            ? "QRScout scan accepted — all 29 fields added and rankings refreshed."
            : "Scan accepted and rankings refreshed."
    };
  }

  function ingestScanFromCell(inputDocument, rowId, columnId) {
    let document = normalizeDocument(inputDocument);
    const source = document.rows.find((row) => row.id === rowId);
    if (!source) return { handled: false, document };
    const raw = source.values[columnId] || "";
    if (!isPackedScan(raw)) return { handled: false, document };

    const hasOtherValues = Object.entries(source.values).some(([key, value]) => (
      key !== columnId && String(value).trim()
    ));
    if (hasOtherValues) return { handled: false, document };

    document.rows = document.rows.filter((row) => row.id !== rowId);
    const result = ingestScan(document, raw);
    if (!result.document.rows.length) result.document.rows.push(blankRow(result.document.columns));
    return { ...result, handled: true };
  }

  function dataQuality(inputDocument) {
    const document = normalizeDocument(inputDocument);
    const teamColumn = document.columns.find((column) => column.role === "teamNumber");
    const matchColumn = document.columns.find((column) => column.role === "matchNumber");
    if (!teamColumn || !matchColumn) {
      return { entryCount: 0, validEntryCount: 0, rowsNeedingAttention: 0, issues: [], matches: [], teams: [] };
    }
    const initialsColumn = document.columns.find((column) => column.name.toLowerCase() === "scouter initials");
    const ratingNames = new Set(["Scoring Efectiveness", "Feeding/Passing Skill", "Defense Skill"]);
    const ratingColumns = document.columns.filter((column) => ratingNames.has(column.name));
    const issues = [];
    const meaningfulRowIds = new Set();
    const matchTeams = new Map();
    const matchEntries = new Map();
    const teamMatches = new Map();
    const pairRows = new Map();
    const addIssue = (row, rowNumber, severity, key, message) => issues.push({ id: `${row.id}-${key}`, rowId: row.id, rowNumber, severity, message });

    document.rows.forEach((row, index) => {
      if (!Object.values(row.values).some((value) => String(value).trim())) return;
      meaningfulRowIds.add(row.id);
      const rowNumber = index + 1;
      const team = Number.parseInt(String(row.values[teamColumn.id] ?? "").trim(), 10);
      const match = Number.parseInt(String(row.values[matchColumn.id] ?? "").trim(), 10);
      if (!Number.isInteger(team) || team <= 0) addIssue(row, rowNumber, "error", "team", "Team number is missing or invalid.");
      if (!Number.isInteger(match) || match <= 0) addIssue(row, rowNumber, "error", "match", "Match number is missing or invalid.");
      if (initialsColumn && !String(row.values[initialsColumn.id] || "").trim()) addIssue(row, rowNumber, "warning", "scouter", "Scouter initials are missing.");
      ratingColumns.forEach((column) => {
        const text = String(row.values[column.id] || "").trim();
        const rating = Number(text);
        if (text && Number.isFinite(rating) && (rating < 0 || rating > 5)) addIssue(row, rowNumber, "warning", column.id, `${column.name} must be between 0 and 5.`);
      });
      if (!Number.isInteger(team) || team <= 0 || !Number.isInteger(match) || match <= 0) return;
      if (!matchTeams.has(match)) matchTeams.set(match, new Set());
      matchTeams.get(match).add(team);
      matchEntries.set(match, (matchEntries.get(match) || 0) + 1);
      if (!teamMatches.has(team)) teamMatches.set(team, []);
      teamMatches.get(team).push(match);
      const key = `${match}-${team}`;
      if (!pairRows.has(key)) pairRows.set(key, []);
      pairRows.get(key).push({ row, rowNumber });
    });

    pairRows.forEach((rows, key) => {
      if (rows.length < 2) return;
      const [match, team] = key.split("-").map(Number);
      rows.forEach(({ row, rowNumber }) => addIssue(row, rowNumber, "warning", "duplicate", `Team ${team} has ${rows.length} entries for match ${match}.`));
    });
    const issueRowIds = new Set(issues.map((issue) => issue.rowId));
    const matches = [...matchTeams.entries()].map(([matchNumber, teams]) => ({
      matchNumber,
      teamNumbers: [...teams].sort((a, b) => a - b),
      entryCount: matchEntries.get(matchNumber),
      missingScoutCount: Math.max(0, 6 - teams.size)
    })).sort((a, b) => a.matchNumber - b.matchNumber);
    const teams = [...teamMatches.entries()].map(([teamNumber, matches]) => ({
      teamNumber,
      entryCount: matches.length,
      latestMatch: Math.max(...matches)
    })).sort((a, b) => a.entryCount - b.entryCount || a.teamNumber - b.teamNumber);
    return {
      entryCount: meaningfulRowIds.size,
      validEntryCount: [...meaningfulRowIds].filter((rowId) => !issueRowIds.has(rowId)).length,
      rowsNeedingAttention: issueRowIds.size,
      issues: issues.sort((a, b) => a.rowNumber - b.rowNumber || (a.severity === "error" ? -1 : 1)),
      matches,
      teams
    };
  }

  function numeric(value) {
    const cleaned = String(value ?? "").trim().replaceAll(",", "");
    if (!cleaned) return null;
    const number = Number(cleaned);
    return Number.isFinite(number) ? number : null;
  }

  function boolean(value) {
    return ["true", "yes", "y", "1", "x", "broken", "broke down"].includes(String(value ?? "").trim().toLowerCase());
  }

  function scoringValue(value, role) {
    const number = numeric(value);
    if (number !== null) return number;
    const code = String(value ?? "").trim().toUpperCase();
    if (role === "autoPoints") return code === "C" ? 15 : 0;
    if (role === "endgamePoints") return { L1: 10, L2: 20, L3: 30 }[code] || 0;
    return 0;
  }

  function average(values) {
    return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : 0;
  }

  function exponentiallyWeightedAverage(values) {
    if (!values.length) return 0;
    const decay = 0.82;
    let weightedTotal = 0;
    let totalWeight = 0;
    values.forEach((value, index) => {
      const weight = decay ** (values.length - index - 1);
      weightedTotal += value * weight;
      totalWeight += weight;
    });
    return weightedTotal / totalWeight;
  }

  function analyze(inputDocument) {
    const document = normalizeDocument(inputDocument);
    const teamColumn = document.columns.find((column) => column.role === "teamNumber");
    if (!teamColumn) return [];
    const matchColumn = document.columns.find((column) => column.role === "matchNumber");
    const byRole = (role) => document.columns.filter((column) => column.role === role);
    const autoColumns = byRole("autoPoints");
    const teleopColumns = byRole("teleopPoints");
    const endgameColumns = byRole("endgamePoints");
    const penaltyColumns = byRole("penaltyPoints");
    const defenseColumns = byRole("defenseRating");
    const breakdownColumns = byRole("breakdown");

    const parsed = document.rows.flatMap((row) => {
      const team = Number.parseInt(String(row.values[teamColumn.id] ?? "").trim(), 10);
      if (!Number.isInteger(team) || team <= 0) return [];
      const sum = (columns, role) => columns.reduce((total, column) => total + (role ? scoringValue(row.values[column.id], role) : (numeric(row.values[column.id]) || 0)), 0);
      const defenseValues = defenseColumns.map((column) => numeric(row.values[column.id])).filter((value) => value !== null);
      const auto = sum(autoColumns, "autoPoints");
      const teleop = sum(teleopColumns, "teleopPoints");
      const endgame = sum(endgameColumns, "endgamePoints");
      const penalties = sum(penaltyColumns);
      return [{
        id: row.id,
        team,
        match: matchColumn ? Number.parseInt(row.values[matchColumn.id] || "0", 10) || 0 : 0,
        auto,
        teleop,
        endgame,
        penalties,
        defense: defenseValues.length ? average(defenseValues) : null,
        brokeDown: breakdownColumns.some((column) => boolean(row.values[column.id])),
        offense: auto + teleop + endgame - penalties
      }];
    });
    if (!parsed.length) return [];

    const leagueMean = average(parsed.map((row) => row.offense));
    const groups = new Map();
    for (const row of parsed) {
      if (!groups.has(row.team)) groups.set(row.team, []);
      groups.get(row.team).push(row);
    }

    return [...groups.entries()].map(([teamNumber, matches]) => {
      const chronological = [...matches].sort((a, b) => a.match - b.match || a.id.localeCompare(b.id));
      const recentAverage = exponentiallyWeightedAverage(chronological.map((match) => match.offense));
      const defenseValues = matches.map((match) => match.defense).filter((value) => value !== null);
      return {
        teamNumber,
        matches: matches.length,
        projectedEPA: (recentAverage * matches.length + leagueMean * 2) / (matches.length + 2),
        averageOffense: average(matches.map((match) => match.offense)),
        averageAuto: average(matches.map((match) => match.auto)),
        averageTeleop: average(matches.map((match) => match.teleop)),
        averageEndgame: average(matches.map((match) => match.endgame)),
        averageDefense: average(defenseValues),
        breakdownRate: matches.filter((match) => match.brokeDown).length / matches.length,
        performances: chronological.map((match) => ({
          id: match.id,
          matchNumber: match.match,
          offensePoints: match.offense,
          defenseRating: match.defense,
          brokeDown: match.brokeDown
        }))
      };
    }).sort((a, b) => b.projectedEPA - a.projectedEPA || a.teamNumber - b.teamNumber);
  }

  function answer(question, teams) {
    if (!teams.length) return "I need at least one row with a valid team number before I can analyze the event.";
    const query = String(question).toLowerCase();
    const requested = [...query.matchAll(/\d+/g)].map((match) => Number(match[0])).map((number) => teams.find((team) => team.teamNumber === number)).filter(Boolean);
    const oneDecimal = (value) => value.toFixed(1);
    const percent = (value) => `${Math.round(value * 100)}%`;
    if (requested.length >= 2) {
      const [a, b] = requested;
      const epaWinner = a.projectedEPA >= b.projectedEPA ? a : b;
      const defenseWinner = a.averageDefense >= b.averageDefense ? a : b;
      const reliabilityWinner = a.breakdownRate <= b.breakdownRate ? a : b;
      return `Team ${epaWinner.teamNumber} leads projected EPA (${oneDecimal(epaWinner.projectedEPA)}). Team ${defenseWinner.teamNumber} has the higher defense rating (${oneDecimal(defenseWinner.averageDefense)}/5), and team ${reliabilityWinner.teamNumber} is more reliable (${percent(1 - reliabilityWinner.breakdownRate)} reliable).`;
    }
    if (requested.length === 1) {
      const team = requested[0];
      return `Team ${team.teamNumber} has a projected EPA of ${oneDecimal(team.projectedEPA)} across ${team.matches} match${team.matches === 1 ? "" : "es"}. It averages ${oneDecimal(team.averageOffense)} offense points and ${oneDecimal(team.averageDefense)}/5 on defense, with a ${percent(team.breakdownRate)} breakdown rate.`;
    }
    let sorted = [...teams].sort((a, b) => b.projectedEPA - a.projectedEPA);
    let label = "projected EPA";
    let value = (team) => team.projectedEPA;
    if (query.includes("break") || query.includes("reliab")) {
      sorted = [...teams].sort((a, b) => a.breakdownRate - b.breakdownRate);
      return `Most reliable teams: ${sorted.slice(0, 5).map((team) => `#${team.teamNumber} (${percent(1 - team.breakdownRate)})`).join(", ")}.`;
    }
    if (query.includes("defen")) {
      sorted = [...teams].sort((a, b) => b.averageDefense - a.averageDefense);
      label = "defense rating";
      value = (team) => team.averageDefense;
    } else if (query.includes("offen") || query.includes("score")) {
      sorted = [...teams].sort((a, b) => b.averageOffense - a.averageOffense);
      label = "average offense";
      value = (team) => team.averageOffense;
    }
    return `Top teams by ${label}: ${sorted.slice(0, 5).map((team) => `#${team.teamNumber} (${oneDecimal(value(team))})`).join(", ")}.`;
  }

  return {
    QRSCOUT_FIELDS,
    HEADER_NAMES,
    qrScoutColumns,
    createDocument,
    normalizeDocument,
    blankRow,
    parseCSV,
    exportCSV,
    importCSV,
    parseScan,
    isPackedScan,
    ingestScan,
    ingestScanFromCell,
    dataQuality,
    analyze,
    answer,
    inferRole,
    isExactQRScoutHeader
  };
});
