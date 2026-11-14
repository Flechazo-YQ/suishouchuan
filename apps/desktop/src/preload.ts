import {contextBridge, ipcRenderer} from 'electron';
import type {DesktopApi} from './types';
const api: DesktopApi = {
  state: () => ipcRenderer.invoke('state'), pair: () => ipcRenderer.invoke('pair'),
  settings: value => ipcRenderer.invoke('settings', value), revoke: id => ipcRenderer.invoke('revoke', id),
  copy: id => ipcRenderer.invoke('copy', id), save: id => ipcRenderer.invoke('save', id), open: id => ipcRenderer.invoke('open', id),
  changed: listener => {const callback = () => listener(); ipcRenderer.on('changed', callback); return () => ipcRenderer.removeListener('changed', callback);},
};
contextBridge.exposeInMainWorld('bridge', api);
