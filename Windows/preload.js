const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("fieldScoutDesktop", Object.freeze({
  loadDocument: () => ipcRenderer.invoke("document:load"),
  saveDocument: (document, forceBackup = false) => ipcRenderer.invoke("document:save", document, forceBackup),
  listBackups: () => ipcRenderer.invoke("backup:list"),
  createBackup: () => ipcRenderer.invoke("backup:create"),
  restoreBackup: (name) => ipcRenderer.invoke("backup:restore", name),
  readClipboardText: () => ipcRenderer.invoke("clipboard:readText"),
  importCSV: () => ipcRenderer.invoke("csv:import"),
  exportCSV: (csvText, suggestedName) => ipcRenderer.invoke("csv:export", csvText, suggestedName),
  platform: "windows"
}));
