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
  checkForUpdates: () => ipcRenderer.invoke("update:check"),
  getPortalStatus: () => ipcRenderer.invoke("portal:status"),
  completePortalSubmission: (requestId, result) => ipcRenderer.invoke("portal:submission-result", requestId, result),
  onPortalSubmission: (callback) => {
    const listener = (_event, request) => callback(request);
    ipcRenderer.on("portal:submission", listener);
    return () => ipcRenderer.removeListener("portal:submission", listener);
  },
  onPortalStatus: (callback) => {
    const listener = (_event, status) => callback(status);
    ipcRenderer.on("portal:status", listener);
    return () => ipcRenderer.removeListener("portal:status", listener);
  },
  onUpdateStatus: (callback) => {
    const listener = (_event, status) => callback(status);
    ipcRenderer.on("update:status", listener);
    return () => ipcRenderer.removeListener("update:status", listener);
  },
  platform: "windows"
}));
