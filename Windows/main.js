const { app, BrowserWindow, clipboard, dialog, ipcMain } = require("electron");
const fs = require("node:fs/promises");
const path = require("node:path");

let mainWindow;
let autoUpdater;
let updateCheckInProgress = false;
let manualUpdateCheck = false;

app.setName("FieldScout");
if (process.platform === "win32") app.setAppUserModelId("org.mecorobotics.fieldscout");

function dataFileURL() {
  return path.join(app.getPath("userData"), "scouting-data.json");
}

function backupDirectoryURL() {
  return path.join(app.getPath("userData"), "Backups");
}

async function listBackups() {
  try {
    const names = await fs.readdir(backupDirectoryURL());
    const snapshots = await Promise.all(names.filter((name) => name.endsWith(".json")).map(async (name) => {
      const filePath = path.join(backupDirectoryURL(), name);
      const stat = await fs.stat(filePath);
      return { name, date: stat.mtime.toISOString() };
    }));
    return snapshots.sort((a, b) => b.date.localeCompare(a.date));
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
}

async function createBackup(force = false) {
  try {
    await fs.access(dataFileURL());
  } catch {
    return listBackups();
  }
  const existing = await listBackups();
  if (!force && existing[0] && Date.now() - Date.parse(existing[0].date) < 300_000) return existing;
  await fs.mkdir(backupDirectoryURL(), { recursive: true });
  const name = `snapshot-${Date.now()}.json`;
  await fs.copyFile(dataFileURL(), path.join(backupDirectoryURL(), name));
  const updated = await listBackups();
  await Promise.all(updated.slice(20).map((backup) => fs.rm(path.join(backupDirectoryURL(), backup.name), { force: true })));
  return listBackups();
}

async function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1500,
    height: 940,
    minWidth: 1050,
    minHeight: 680,
    backgroundColor: "#07111f",
    icon: path.join(__dirname, "assets", "AppIcon.png"),
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });

  await mainWindow.loadFile(path.join(__dirname, "src", "index.html"));
}

function sendUpdateStatus(status) {
  if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send("update:status", status);
}

async function checkForUpdates(userInitiated = false) {
  if (!autoUpdater) {
    const message = app.isPackaged
      ? "Automatic updates are only available in the installed Windows app."
      : "Update checks are available in packaged builds.";
    if (userInitiated) sendUpdateStatus({ state: "error", message });
    return { started: false, message };
  }
  if (updateCheckInProgress) return { started: false, message: "An update check is already running." };

  manualUpdateCheck = userInitiated;
  updateCheckInProgress = true;
  sendUpdateStatus({ state: "checking", message: "Checking for updates…" });
  try {
    await autoUpdater.checkForUpdates();
    return { started: true };
  } catch (error) {
    updateCheckInProgress = false;
    if (userInitiated) sendUpdateStatus({ state: "error", message: `Update check failed: ${error.message}` });
    else sendUpdateStatus({ state: "idle", message: "" });
    console.error("FieldScout update check failed:", error);
    return { started: false, message: error.message };
  }
}

function configureAutomaticUpdates() {
  if (!app.isPackaged || process.platform !== "win32") return;

  ({ autoUpdater } = require("electron-updater"));
  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = true;
  autoUpdater.logger = console;

  autoUpdater.on("update-available", (info) => {
    sendUpdateStatus({ state: "downloading", message: `Downloading FieldScout ${info.version}…`, version: info.version });
  });
  autoUpdater.on("download-progress", (progress) => {
    sendUpdateStatus({
      state: "downloading",
      message: `Downloading update… ${Math.round(progress.percent)}%`,
      percent: progress.percent
    });
  });
  autoUpdater.on("update-not-available", () => {
    updateCheckInProgress = false;
    if (manualUpdateCheck) sendUpdateStatus({ state: "current", message: "FieldScout is up to date." });
    else sendUpdateStatus({ state: "idle", message: "" });
    manualUpdateCheck = false;
  });
  autoUpdater.on("error", (error) => {
    updateCheckInProgress = false;
    if (manualUpdateCheck) sendUpdateStatus({ state: "error", message: `Update failed: ${error.message}` });
    else sendUpdateStatus({ state: "idle", message: "" });
    manualUpdateCheck = false;
    console.error("FieldScout updater error:", error);
  });
  autoUpdater.on("update-downloaded", async (info) => {
    updateCheckInProgress = false;
    manualUpdateCheck = false;
    sendUpdateStatus({ state: "ready", message: `FieldScout ${info.version} is ready to install.`, version: info.version });
    const result = await dialog.showMessageBox(mainWindow, {
      type: "info",
      title: "FieldScout update ready",
      message: `FieldScout ${info.version} has been downloaded.`,
      detail: "Restart FieldScout to finish the update. Your scouting data and backups will stay in place.",
      buttons: ["Restart and update", "Later"],
      defaultId: 0,
      cancelId: 1
    });
    if (result.response === 0) autoUpdater.quitAndInstall(false, true);
  });

  setTimeout(() => checkForUpdates(false), 5_000);
  setInterval(() => checkForUpdates(false), 6 * 60 * 60 * 1_000);
}

ipcMain.handle("document:load", async () => {
  try {
    return JSON.parse(await fs.readFile(dataFileURL(), "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    const backups = await listBackups();
    for (const backup of backups) {
      try {
        return JSON.parse(await fs.readFile(path.join(backupDirectoryURL(), backup.name), "utf8"));
      } catch { /* Try the next snapshot. */ }
    }
    throw error;
  }
});

ipcMain.handle("document:save", async (_event, document, forceBackup = false) => {
  const encoded = JSON.stringify(document, null, 2);
  if (encoded.length > 50_000_000) throw new Error("The scouting document is too large to save.");
  await fs.mkdir(path.dirname(dataFileURL()), { recursive: true });
  try {
    await createBackup(forceBackup);
  } catch (error) {
    console.error("Could not create scouting backup before save:", error);
  }
  await fs.writeFile(dataFileURL(), encoded, "utf8");
  return true;
});

ipcMain.handle("backup:list", listBackups);
ipcMain.handle("backup:create", () => createBackup(true));
ipcMain.handle("backup:restore", async (_event, name) => {
  if (path.basename(name) !== name || !name.endsWith(".json")) throw new Error("Invalid backup name.");
  return JSON.parse(await fs.readFile(path.join(backupDirectoryURL(), name), "utf8"));
});
ipcMain.handle("clipboard:readText", () => clipboard.readText());
ipcMain.handle("update:check", () => checkForUpdates(true));

ipcMain.handle("csv:import", async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: "Import scouting CSV",
    properties: ["openFile"],
    filters: [{ name: "CSV files", extensions: ["csv"] }]
  });
  if (result.canceled || result.filePaths.length === 0) return { canceled: true };
  const filePath = result.filePaths[0];
  return {
    canceled: false,
    name: path.basename(filePath, path.extname(filePath)),
    text: await fs.readFile(filePath, "utf8")
  };
});

ipcMain.handle("csv:export", async (_event, csvText, suggestedName) => {
  const result = await dialog.showSaveDialog(mainWindow, {
    title: "Export scouting CSV",
    defaultPath: `${suggestedName || "FieldScout"}.csv`,
    filters: [{ name: "CSV files", extensions: ["csv"] }]
  });
  if (result.canceled || !result.filePath) return { canceled: true };
  await fs.writeFile(result.filePath, csvText, "utf8");
  return { canceled: false, path: result.filePath };
});

app.whenReady().then(async () => {
  await createWindow();
  configureAutomaticUpdates();
  app.on("activate", async () => {
    if (BrowserWindow.getAllWindows().length === 0) await createWindow();
  });
});

app.on("window-all-closed", () => app.quit());
