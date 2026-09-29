(function startFieldScout() {
  "use strict";

  const core = window.FieldScoutCore;
  const desktop = window.fieldScoutDesktop;
  const state = {
    document: core.createDocument(),
    teams: [],
    view: "sheet",
    rankingMetric: "epa",
    selectedTeam: null,
    acceptedScans: 0,
    saveTimer: null,
    forceBackupOnSave: false,
    undoStack: [],
    redoStack: [],
    lastMutationKey: null,
    lastMutationAt: 0,
    pendingConflict: null,
    backups: []
  };

  const byId = (id) => document.getElementById(id);

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function meaningfulRowCount() {
    return state.document.rows.filter((row) => Object.values(row.values).some((value) => String(value).trim())).length;
  }

  function showSaveStatus(text, isError = false) {
    const node = byId("save-status");
    node.textContent = text;
    node.style.color = isError ? "#ff8999" : "";
  }

  function snapshotDocument() {
    return JSON.parse(JSON.stringify(state.document));
  }

  function recordUndo(coalescingKey = null) {
    const now = Date.now();
    if (coalescingKey && state.lastMutationKey === coalescingKey && now - state.lastMutationAt < 1000) {
      state.lastMutationAt = now;
      return;
    }
    state.undoStack.push(snapshotDocument());
    if (state.undoStack.length > 50) state.undoStack.shift();
    state.redoStack = [];
    state.lastMutationKey = coalescingKey;
    state.lastMutationAt = now;
    updateHistoryButtons();
  }

  function updateHistoryButtons() {
    byId("undo-button").disabled = state.undoStack.length === 0;
    byId("redo-button").disabled = state.redoStack.length === 0;
  }

  function undo() {
    const previous = state.undoStack.pop();
    if (!previous) return;
    state.redoStack.push(snapshotDocument());
    state.document = previous;
    state.lastMutationKey = null;
    scheduleSave();
    renderAll();
  }

  function redo() {
    const next = state.redoStack.pop();
    if (!next) return;
    state.undoStack.push(snapshotDocument());
    state.document = next;
    state.lastMutationKey = null;
    scheduleSave();
    renderAll();
  }

  function scheduleSave(forceBackup = false) {
    state.document.updatedAt = new Date().toISOString();
    state.forceBackupOnSave ||= forceBackup;
    showSaveStatus("Saving locally…");
    window.clearTimeout(state.saveTimer);
    state.saveTimer = window.setTimeout(async () => {
      try {
        const createBackup = state.forceBackupOnSave;
        state.forceBackupOnSave = false;
        await desktop.saveDocument(state.document, createBackup);
        showSaveStatus("Stored locally");
        if (state.view === "status") await renderStatus();
      } catch (error) {
        showSaveStatus(`Save failed: ${error.message}`, true);
      }
    }, 180);
    updateHistoryButtons();
  }

  function refreshAnalytics() {
    state.teams = core.analyze(state.document);
    if (!state.selectedTeam || !state.teams.some((team) => team.teamNumber === state.selectedTeam)) {
      state.selectedTeam = state.teams[0]?.teamNumber || null;
    }
    renderRankings();
    renderTeamOptions();
    if (state.view === "charts") renderCharts();
  }

  function roleLabel(role) {
    return ({
      teamNumber: "Team",
      matchNumber: "Match",
      autoPoints: "Auto scoring",
      teleopPoints: "Teleop scoring",
      endgamePoints: "Endgame",
      penaltyPoints: "Penalty",
      defenseRating: "Defense",
      breakdown: "Breakdown",
      none: "Data"
    })[role] || "Data";
  }

  const analyticsRoles = [
    "none",
    "teamNumber",
    "matchNumber",
    "autoPoints",
    "teleopPoints",
    "endgamePoints",
    "penaltyPoints",
    "defenseRating",
    "breakdown"
  ];

  function renderSheet() {
    const container = byId("sheet-container");
    const quality = core.dataQuality(state.document);
    const issueRows = new Set(quality.issues.map((issue) => issue.rowId));
    const table = element("table");
    const head = element("thead");
    const headerRow = element("tr");
    const numberHeader = element("th", "row-number", "#");
    headerRow.append(numberHeader);
    state.document.columns.forEach((column) => {
      const header = element("th", "", column.name);
      header.title = `${column.name} · ${roleLabel(column.role)}`;
      const roleSelect = element("select", "role-select");
      roleSelect.setAttribute("aria-label", `Analytics role for ${column.name}`);
      analyticsRoles.forEach((role) => {
        const option = element("option", "", roleLabel(role));
        option.value = role;
        option.selected = role === column.role;
        roleSelect.append(option);
      });
      roleSelect.addEventListener("change", () => {
        recordUndo();
        column.role = roleSelect.value;
        scheduleSave();
        refreshAnalytics();
      });
      header.append(roleSelect);
      headerRow.append(header);
    });
    headerRow.append(element("th", "action-column", ""));
    head.append(headerRow);
    table.append(head);

    const body = element("tbody");
    state.document.rows.forEach((row, rowIndex) => {
      const tr = element("tr");
      tr.append(element("td", `row-number${issueRows.has(row.id) ? " issue" : ""}`, issueRows.has(row.id) ? `⚠ ${rowIndex + 1}` : String(rowIndex + 1)));
      state.document.columns.forEach((column) => {
        const td = element("td", column.type === "boolean" ? "checkbox-cell" : "");
        const input = document.createElement("input");
        input.dataset.row = row.id;
        input.dataset.column = column.id;
        input.setAttribute("aria-label", `${column.name}, row ${rowIndex + 1}`);
        if (column.type === "boolean") {
          input.type = "checkbox";
          input.checked = ["true", "yes", "1", "x"].includes(String(row.values[column.id] || "").toLowerCase());
          input.addEventListener("change", () => {
            recordUndo(`cell-${row.id}-${column.id}`);
            row.values[column.id] = input.checked ? "true" : "false";
            scheduleSave();
            refreshAnalytics();
          });
        } else {
          input.type = column.type === "integer" || column.type === "decimal" ? "number" : "text";
          if (column.type === "decimal") input.step = "any";
          input.value = row.values[column.id] || "";
          input.addEventListener("input", () => {
            recordUndo(`cell-${row.id}-${column.id}`);
            row.values[column.id] = input.value;
            scheduleSave();
            refreshAnalytics();
            updateCounts();
          });
        }
        td.append(input);
        tr.append(td);
      });
      const action = element("td", "action-column");
      const remove = element("button", "delete-row", "×");
      remove.type = "button";
      remove.title = `Delete row ${rowIndex + 1}`;
      remove.addEventListener("click", () => {
        if (!window.confirm(`Delete row ${rowIndex + 1}?`)) return;
        recordUndo();
        state.document.rows = state.document.rows.filter((candidate) => candidate.id !== row.id);
        if (state.document.rows.length === 0) state.document.rows.push(core.blankRow(state.document.columns));
        scheduleSave(true);
        renderAll();
      });
      action.append(remove);
      tr.append(action);
      body.append(tr);
    });
    table.append(body);
    container.replaceChildren(table);
    updateCounts();
  }

  function updateCounts() {
    const rows = meaningfulRowCount();
    byId("row-count").textContent = `${rows} ${rows === 1 ? "entry" : "entries"}`;
    byId("team-count").textContent = `${state.teams.length} ${state.teams.length === 1 ? "team" : "teams"}`;
    byId("scan-count").textContent = `${state.acceptedScans} accepted this session`;
  }

  function rankingConfiguration() {
    return ({
      epa: { sort: (a, b) => b.projectedEPA - a.projectedEPA, value: (team) => team.projectedEPA.toFixed(1), label: "EPA" },
      breakdown: { sort: (a, b) => a.breakdownRate - b.breakdownRate, value: (team) => `${Math.round(team.breakdownRate * 100)}%`, label: "breakdown" },
      offense: { sort: (a, b) => b.averageOffense - a.averageOffense, value: (team) => team.averageOffense.toFixed(1), label: "offense" },
      defense: { sort: (a, b) => b.averageDefense - a.averageDefense, value: (team) => `${team.averageDefense.toFixed(1)}/5`, label: "defense" }
    })[state.rankingMetric];
  }

  function annotationFor(teamNumber) {
    return state.document.teamAnnotations.find((annotation) => annotation.teamNumber === teamNumber)
      || { teamNumber, flag: "none", note: "" };
  }

  function flagGlyph(flag) {
    return ({ favorite: "★", watch: "◉", doNotPick: "⛔", none: "" })[flag] || "";
  }

  function updateAnnotation(teamNumber, flag, note, coalesce = false) {
    recordUndo(coalesce ? `annotation-${teamNumber}` : null);
    state.document.teamAnnotations = state.document.teamAnnotations.filter((annotation) => annotation.teamNumber !== teamNumber);
    if (flag !== "none" || String(note).trim()) state.document.teamAnnotations.push({ teamNumber, flag, note });
    scheduleSave();
    renderRankings();
  }

  function renderRankings() {
    const list = byId("ranking-list");
    list.replaceChildren();
    updateCounts();
    if (!state.teams.length) {
      list.append(element("div", "empty", "Enter or scan a team number to begin ranking teams."));
      return;
    }
    const config = rankingConfiguration();
    [...state.teams].sort(config.sort).forEach((team, index) => {
      const row = element("div", "ranking-row");
      row.append(element("span", "rank-number", `#${index + 1}`));
      const identity = element("div");
      const annotation = annotationFor(team.teamNumber);
      identity.append(element("div", "team-name", `${flagGlyph(annotation.flag)}${annotation.flag === "none" ? "" : " "}Team ${team.teamNumber}`));
      identity.title = annotation.note || (annotation.flag === "none" ? "" : annotation.flag);
      identity.append(element("div", "team-matches", `${team.matches} ${team.matches === 1 ? "match" : "matches"}`));
      row.append(identity);
      const value = element("div", "rank-value", config.value(team));
      value.title = config.label;
      row.append(value);
      row.addEventListener("dblclick", () => {
        state.selectedTeam = team.teamNumber;
        switchView("charts");
      });
      list.append(row);
    });
  }

  function renderTeamOptions() {
    const select = byId("team-select");
    select.replaceChildren();
    if (!state.teams.length) {
      const option = element("option", "", "No teams yet");
      option.value = "";
      select.append(option);
      select.disabled = true;
      return;
    }
    select.disabled = false;
    state.teams.forEach((team) => {
      const option = element("option", "", `Team ${team.teamNumber}`);
      option.value = String(team.teamNumber);
      option.selected = team.teamNumber === state.selectedTeam;
      select.append(option);
    });
  }

  function statCard(label, value) {
    const card = element("article", "card stat-card");
    card.append(element("span", "", label));
    card.append(element("strong", "", value));
    return card;
  }

  function barRow(label, value, maximum, red = false) {
    const row = element("div", "bar-row");
    row.append(element("span", "", label));
    const track = element("div", "bar-track");
    const fill = element("div", `bar-fill${red ? " red" : ""}`);
    fill.style.width = `${Math.max(0, Math.min(100, maximum ? (value / maximum) * 100 : 0))}%`;
    track.append(fill);
    row.append(track);
    row.append(element("strong", "", value.toFixed(1)));
    return row;
  }

  function renderCharts() {
    const content = byId("chart-content");
    content.replaceChildren();
    const team = state.teams.find((candidate) => candidate.teamNumber === state.selectedTeam);
    if (!team) {
      content.append(element("div", "empty", "Add scouting entries to see team charts."));
      return;
    }
    const annotation = annotationFor(team.teamNumber);
    const annotationCard = element("div", "card team-annotation");
    const flagSelect = element("select");
    [
      ["none", "No flag"],
      ["favorite", "★ Favorite"],
      ["watch", "◉ Watch"],
      ["doNotPick", "⛔ Do Not Pick"]
    ].forEach(([value, label]) => {
      const option = element("option", "", label);
      option.value = value;
      option.selected = value === annotation.flag;
      flagSelect.append(option);
    });
    const noteInput = element("input");
    noteInput.placeholder = "Short team note";
    noteInput.value = annotation.note;
    flagSelect.addEventListener("change", () => {
      updateAnnotation(team.teamNumber, flagSelect.value, noteInput.value);
      renderCharts();
    });
    noteInput.addEventListener("input", () => updateAnnotation(team.teamNumber, flagSelect.value, noteInput.value, true));
    annotationCard.append(flagSelect, noteInput);
    content.append(annotationCard);

    const stats = element("div", "stat-grid");
    stats.append(statCard("Projected EPA", team.projectedEPA.toFixed(1)));
    stats.append(statCard("Average offense", team.averageOffense.toFixed(1)));
    stats.append(statCard("Defense skill", `${team.averageDefense.toFixed(1)}/5`));
    stats.append(statCard("Breakdown rate", `${Math.round(team.breakdownRate * 100)}%`));
    content.append(stats);

    const grid = element("div", "chart-grid");
    const composition = element("article", "card chart-card");
    composition.append(element("h3", "", "Average scoring composition"));
    const maximum = Math.max(team.averageAuto, team.averageTeleop, team.averageEndgame, 1);
    composition.append(barRow("Auto", team.averageAuto, maximum));
    composition.append(barRow("Teleop", team.averageTeleop, maximum));
    composition.append(barRow("Endgame", team.averageEndgame, maximum));
    grid.append(composition);

    const trend = element("article", "card chart-card");
    trend.append(element("h3", "", "Match offense trend"));
    const bars = element("div", "match-bars");
    const matchMax = Math.max(...team.performances.map((performance) => performance.offensePoints), 1);
    team.performances.forEach((performance) => {
      const column = element("div", `match-column${performance.brokeDown ? " broke" : ""}`);
      const bar = element("i");
      bar.style.height = `${Math.max(2, (performance.offensePoints / matchMax) * 185)}px`;
      bar.title = `${performance.offensePoints.toFixed(1)} offense points${performance.brokeDown ? " · breakdown" : ""}`;
      column.append(bar);
      column.append(element("span", "", `M${performance.matchNumber}`));
      bars.append(column);
    });
    trend.append(bars);
    grid.append(trend);
    content.append(grid);
  }

  async function renderStatus() {
    const quality = core.dataQuality(state.document);
    const summary = byId("status-summary");
    summary.replaceChildren(
      statCard("Scouting entries", String(quality.entryCount)),
      statCard("Valid", String(quality.validEntryCount)),
      statCard("Need attention", String(quality.rowsNeedingAttention)),
      statCard("Teams covered", String(quality.teams.length))
    );

    const qualityList = byId("quality-list");
    qualityList.replaceChildren();
    if (!quality.issues.length) {
      qualityList.append(element("p", "status-empty", "No missing identifiers, duplicate team-match entries, or invalid 0–5 ratings were found."));
    } else {
      quality.issues.slice(0, 12).forEach((issue) => {
        const item = element("button", `quality-item ${issue.severity}`);
        item.append(element("strong", "", `Row ${issue.rowNumber}`));
        item.append(element("span", "", issue.message));
        item.addEventListener("click", () => switchView("sheet"));
        qualityList.append(item);
      });
      if (quality.issues.length > 12) qualityList.append(element("p", "status-empty", `${quality.issues.length - 12} more issues are highlighted in the sheet.`));
    }

    const matchCoverage = byId("match-coverage");
    matchCoverage.replaceChildren();
    if (!quality.matches.length) {
      matchCoverage.append(element("p", "status-empty", "Valid match and team numbers will appear here."));
    } else {
      quality.matches.slice(-12).forEach((match) => {
        const row = element("div", "coverage-item");
        row.append(element("strong", "", `Match ${match.matchNumber}`));
        const track = element("div", "mini-track");
        const fill = element("div", "mini-fill");
        fill.style.width = `${Math.min(100, (match.teamNumbers.length / 6) * 100)}%`;
        track.append(fill);
        row.append(track);
        row.append(element("span", "", `${match.teamNumbers.length} / 6 teams`));
        matchCoverage.append(row);
      });
    }

    const teamCoverage = byId("team-coverage");
    teamCoverage.replaceChildren();
    if (!quality.teams.length) {
      teamCoverage.append(element("p", "status-empty", "Scouted teams will appear here."));
    } else {
      quality.teams.slice(0, 14).forEach((team) => {
        const row = element("div", "coverage-item");
        row.append(element("strong", "", `Team ${team.teamNumber}`));
        row.append(element("span", "", `${team.entryCount} entries`));
        row.append(element("span", "", `Latest M${team.latestMatch}`));
        teamCoverage.append(row);
      });
    }

    const backupList = byId("backup-list");
    backupList.replaceChildren();
    try {
      state.backups = await desktop.listBackups();
      if (!state.backups.length) {
        backupList.append(element("p", "status-empty", "Backups are created automatically while the sheet changes and before destructive actions."));
      } else {
        state.backups.slice(0, 8).forEach((backup) => {
          const row = element("div", "backup-item");
          row.append(element("span", "", new Date(backup.date).toLocaleString()));
          const restore = element("button", "secondary", "Restore");
          restore.addEventListener("click", async () => {
            if (!window.confirm("Restore this backup? The current sheet will be backed up first.")) return;
            try {
              await desktop.createBackup();
              const restored = await desktop.restoreBackup(backup.name);
              recordUndo();
              state.document = core.normalizeDocument(restored);
              await desktop.saveDocument(state.document, false);
              renderAll();
              await renderStatus();
              showSaveStatus("Backup restored");
            } catch (error) {
              window.alert(`Could not restore backup: ${error.message}`);
            }
          });
          row.append(restore);
          backupList.append(row);
        });
      }
    } catch (error) {
      backupList.append(element("p", "status-empty", `Could not list backups: ${error.message}`));
    }
  }

  function renderAll() {
    state.document = core.normalizeDocument(state.document);
    state.teams = core.analyze(state.document);
    renderSheet();
    refreshAnalytics();
    updateCounts();
    updateHistoryButtons();
    if (state.view === "status") renderStatus();
  }

  function switchView(view) {
    state.view = view;
    document.querySelectorAll(".view").forEach((section) => section.classList.toggle("active", section.id === `${view}-view`));
    document.querySelectorAll(".nav-button").forEach((button) => button.classList.toggle("active", button.dataset.view === view));
    if (view === "scanner") window.setTimeout(() => byId("scanner-input").focus(), 30);
    if (view === "status") renderStatus();
    if (view === "charts") renderCharts();
  }

  function addRow() {
    recordUndo();
    state.document.rows.push(core.blankRow(state.document.columns));
    scheduleSave();
    renderSheet();
    const container = byId("sheet-container");
    container.scrollTop = container.scrollHeight;
  }

  async function importCSV() {
    if (meaningfulRowCount() && !window.confirm("Importing replaces the open sheet. Continue?")) return;
    try {
      const result = await desktop.importCSV();
      if (result.canceled) return;
      await desktop.createBackup();
      recordUndo();
      state.document = core.importCSV(result.text, result.name);
      if (state.document.rows.length === 0) state.document.rows.push(core.blankRow(state.document.columns));
      scheduleSave();
      renderAll();
      switchView("sheet");
    } catch (error) {
      window.alert(`Could not import CSV: ${error.message}`);
    }
  }

  async function pasteRows() {
    const text = await desktop.readClipboardText();
    const records = String(text).split(/\r?\n/).filter((line) => line.length > 0).map((line) => line.split("\t"));
    if (!records.length) {
      showSaveStatus("Clipboard has no tab-separated rows", true);
      return;
    }
    recordUndo();
    state.document.rows = state.document.rows.filter((row) => Object.values(row.values).some((value) => String(value).trim()));
    records.forEach((record) => {
      const row = core.blankRow(state.document.columns);
      record.slice(0, state.document.columns.length).forEach((value, index) => { row.values[state.document.columns[index].id] = value; });
      state.document.rows.push(row);
    });
    scheduleSave();
    renderAll();
    switchView("sheet");
    showSaveStatus(`Pasted ${records.length} row${records.length === 1 ? "" : "s"}`);
  }

  async function exportCSV() {
    try {
      const result = await desktop.exportCSV(core.exportCSV(state.document), state.document.title);
      if (!result.canceled) showSaveStatus("CSV exported");
    } catch (error) {
      window.alert(`Could not export CSV: ${error.message}`);
    }
  }

  function showConflict(conflict) {
    state.pendingConflict = conflict;
    byId("conflict-title").textContent = `Team ${conflict.teamNumber}, match ${conflict.matchNumber}`;
    byId("conflict-description").textContent = "This team and match already exist. Compare the changed fields, then replace the old row or keep both entries.";
    const body = byId("conflict-body");
    body.replaceChildren();
    conflict.differences.forEach((difference) => {
      const row = element("tr");
      row.append(element("td", "", difference.columnName));
      row.append(element("td", "", difference.previousValue || "—"));
      row.append(element("td", "", difference.scannedValue || "—"));
      body.append(row);
    });
    byId("conflict-dialog").showModal();
  }

  function cancelConflict() {
    state.pendingConflict = null;
    byId("conflict-dialog").close();
    byId("scanner-status").textContent = "Conflicting scan cancelled; the existing row was not changed.";
    byId("scanner-input").focus();
  }

  function resolveConflict(resolution) {
    if (!state.pendingConflict) return;
    try {
      recordUndo();
      const result = core.ingestScan(state.document, state.pendingConflict.rawPayload, resolution);
      state.document = result.document;
      state.pendingConflict = null;
      byId("conflict-dialog").close();
      byId("scanner-status").textContent = result.message;
      byId("scanner-status").className = "message success";
      byId("scanner-input").value = "";
      state.acceptedScans += 1;
      scheduleSave(true);
      renderAll();
      byId("scanner-input").focus();
    } catch (error) {
      window.alert(`Could not resolve scan: ${error.message}`);
    }
  }

  function acceptScan() {
    const input = byId("scanner-input");
    const status = byId("scanner-status");
    try {
      const previousDocument = snapshotDocument();
      const result = core.ingestScan(state.document, input.value);
      state.document = result.document;
      status.textContent = result.message;
      status.className = `message ${result.accepted ? "success" : ""}`;
      if (result.conflict) {
        showConflict(result.conflict);
      } else if (result.accepted) {
        state.undoStack.push(previousDocument);
        if (state.undoStack.length > 50) state.undoStack.shift();
        state.redoStack = [];
        updateHistoryButtons();
        state.acceptedScans += 1;
        input.value = "";
        scheduleSave();
        renderAll();
      } else {
        input.value = "";
      }
    } catch (error) {
      status.textContent = error.message;
      status.className = "message error";
    }
    input.focus();
    updateCounts();
  }

  function bindEvents() {
    document.querySelectorAll(".nav-button").forEach((button) => button.addEventListener("click", () => switchView(button.dataset.view)));
    byId("add-row-button").addEventListener("click", () => { switchView("sheet"); addRow(); });
    byId("undo-button").addEventListener("click", undo);
    byId("redo-button").addEventListener("click", redo);
    byId("paste-rows-button").addEventListener("click", pasteRows);
    byId("import-button").addEventListener("click", importCSV);
    byId("export-button").addEventListener("click", exportCSV);
    byId("ranking-metric").addEventListener("change", (event) => { state.rankingMetric = event.target.value; renderRankings(); });
    byId("team-select").addEventListener("change", (event) => { state.selectedTeam = Number(event.target.value) || null; renderCharts(); });
    byId("accept-scan-button").addEventListener("click", acceptScan);
    byId("clear-scan-button").addEventListener("click", () => { byId("scanner-input").value = ""; byId("scanner-input").focus(); });
    byId("conflict-close").addEventListener("click", cancelConflict);
    byId("conflict-cancel").addEventListener("click", cancelConflict);
    byId("conflict-keep").addEventListener("click", () => resolveConflict("keep"));
    byId("conflict-replace").addEventListener("click", () => resolveConflict("replace"));
    byId("create-backup-button").addEventListener("click", async () => {
      try {
        state.backups = await desktop.createBackup();
        await renderStatus();
        showSaveStatus("Backup created");
      } catch (error) {
        window.alert(`Could not create backup: ${error.message}`);
      }
    });
    byId("scanner-input").addEventListener("keydown", (event) => {
      if (event.key === "Tab") {
        event.preventDefault();
        const input = event.currentTarget;
        const start = input.selectionStart;
        input.setRangeText("\t", start, input.selectionEnd, "end");
      } else if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault();
        acceptScan();
      }
    });
    byId("analyst-form").addEventListener("submit", (event) => {
      event.preventDefault();
      const question = byId("analyst-question").value;
      byId("analyst-answer").textContent = core.answer(question, state.teams);
    });
    document.querySelectorAll("[data-question]").forEach((button) => button.addEventListener("click", () => {
      byId("analyst-question").value = button.dataset.question;
      byId("analyst-answer").textContent = core.answer(button.dataset.question, state.teams);
    }));
    document.addEventListener("keydown", (event) => {
      if (!(event.ctrlKey || event.metaKey) || event.key.toLowerCase() !== "z") return;
      event.preventDefault();
      if (event.shiftKey) redo(); else undo();
    });
  }

  async function initialize() {
    bindEvents();
    try {
      state.document = core.normalizeDocument(await desktop.loadDocument());
    } catch (error) {
      state.document = core.createDocument();
      showSaveStatus(`Using a new local sheet: ${error.message}`, true);
    }
    renderAll();
  }

  initialize();
})();
