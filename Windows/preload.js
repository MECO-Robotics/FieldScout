const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("fieldScoutDesktop", Object.freeze({
  loadDocument: () => ipcRenderer.invoke("document:load"),
  saveDocument: (document) => ipcRenderer.invoke("document:save", document),
  importCSV: () => ipcRenderer.invoke("csv:import"),
  exportCSV: (csvText, suggestedName) => ipcRenderer.invoke("csv:export", csvText, suggestedName),
  platform: "windows"
}));
