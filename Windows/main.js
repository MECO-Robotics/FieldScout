const { app, BrowserWindow, dialog, ipcMain } = require("electron");
const fs = require("node:fs/promises");
const path = require("node:path");

let mainWindow;

app.setName("FieldScout");
if (process.platform === "win32") app.setAppUserModelId("org.mecorobotics.fieldscout");

function dataFileURL() {
  return path.join(app.getPath("userData"), "scouting-data.json");
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

ipcMain.handle("document:load", async () => {
  try {
    return JSON.parse(await fs.readFile(dataFileURL(), "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
});

ipcMain.handle("document:save", async (_event, document) => {
  const encoded = JSON.stringify(document, null, 2);
  if (encoded.length > 50_000_000) throw new Error("The scouting document is too large to save.");
  await fs.mkdir(path.dirname(dataFileURL()), { recursive: true });
  await fs.writeFile(dataFileURL(), encoded, "utf8");
  return true;
});

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
  app.on("activate", async () => {
    if (BrowserWindow.getAllWindows().length === 0) await createWindow();
  });
});

app.on("window-all-closed", () => app.quit());
