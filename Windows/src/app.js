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
    saveTimer: null
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

  function scheduleSave() {
    state.document.updatedAt = new Date().toISOString();
    showSaveStatus("Saving locally…");
    window.clearTimeout(state.saveTimer);
    state.saveTimer = window.setTimeout(async () => {
      try {
        await desktop.saveDocument(state.document);
        showSaveStatus("Stored locally");
      } catch (error) {
        showSaveStatus(`Save failed: ${error.message}`, true);
      }
    }, 180);
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
      tr.append(element("td", "row-number", String(rowIndex + 1)));
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
            row.values[column.id] = input.checked ? "true" : "false";
            scheduleSave();
            refreshAnalytics();
          });
        } else {
          input.type = column.type === "integer" || column.type === "decimal" ? "number" : "text";
          if (column.type === "decimal") input.step = "any";
          input.value = row.values[column.id] || "";
          input.addEventListener("input", () => {
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
        state.document.rows = state.document.rows.filter((candidate) => candidate.id !== row.id);
        if (state.document.rows.length === 0) state.document.rows.push(core.blankRow(state.document.columns));
        scheduleSave();
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
      identity.append(element("div", "team-name", `Team ${team.teamNumber}`));
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

  function renderAll() {
    state.document = core.normalizeDocument(state.document);
    state.teams = core.analyze(state.document);
    renderSheet();
    refreshAnalytics();
    updateCounts();
  }

  function switchView(view) {
    state.view = view;
    document.querySelectorAll(".view").forEach((section) => section.classList.toggle("active", section.id === `${view}-view`));
    document.querySelectorAll(".nav-button").forEach((button) => button.classList.toggle("active", button.dataset.view === view));
    if (view === "scanner") window.setTimeout(() => byId("scanner-input").focus(), 30);
    if (view === "charts") renderCharts();
  }

  function addRow() {
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
      state.document = core.importCSV(result.text, result.name);
      if (state.document.rows.length === 0) state.document.rows.push(core.blankRow(state.document.columns));
      scheduleSave();
      renderAll();
      switchView("sheet");
    } catch (error) {
      window.alert(`Could not import CSV: ${error.message}`);
    }
  }

  async function exportCSV() {
    try {
      const result = await desktop.exportCSV(core.exportCSV(state.document), state.document.title);
      if (!result.canceled) showSaveStatus("CSV exported");
    } catch (error) {
      window.alert(`Could not export CSV: ${error.message}`);
    }
  }

  function acceptScan() {
    const input = byId("scanner-input");
    const status = byId("scanner-status");
    try {
      const result = core.ingestScan(state.document, input.value);
      state.document = result.document;
      status.textContent = result.message;
      status.className = `message ${result.accepted ? "success" : ""}`;
      if (result.accepted) {
        state.acceptedScans += 1;
        input.value = "";
        scheduleSave();
        renderAll();
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
    byId("import-button").addEventListener("click", importCSV);
    byId("export-button").addEventListener("click", exportCSV);
    byId("ranking-metric").addEventListener("change", (event) => { state.rankingMetric = event.target.value; renderRankings(); });
    byId("team-select").addEventListener("change", (event) => { state.selectedTeam = Number(event.target.value) || null; renderCharts(); });
    byId("accept-scan-button").addEventListener("click", acceptScan);
    byId("clear-scan-button").addEventListener("click", () => { byId("scanner-input").value = ""; byId("scanner-input").focus(); });
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
