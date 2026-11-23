import {app, BrowserWindow, ClipboardItem, clipboard, dialog, ipcMain, Menu, nativeImage, safeStorage, screen, shell, Tray} from 'electron';
import fs from 'node:fs';
import path from 'node:path';
import {randomBytes} from 'node:crypto';
import http from 'node:http';
import {pathToFileURL} from 'node:url';
import {Bonjour} from 'bonjour-service';
import QRCode from 'qrcode';
import {Store} from './store';
import {Receiver, addresses, isPrivate} from './receiver';
import type {DesktopState, Settings, Transfer} from './types';
import {copyMacFiles, copyMacImage} from './macPlatform';
import {MAX_BATCH_IMAGES} from './batch';

const isMac = process.platform === 'darwin';
const appName = isMac ? 'CommandV' : 'CtrlV';
app.setName(appName);
// Keep the existing identity, pairing credentials and cache when the display name changes.
app.setPath('userData', path.join(app.getPath('appData'), isMac ? 'CommandV' : '随手传'));
if (!isMac) app.setAppUserModelId('cn.local.imagebridge');
const testOutput = process.argv.find(value => value.startsWith('--self-test='))?.slice(12);
const testDirectory = process.argv.find(value => value.startsWith('--data-dir='))?.slice(11);
if (testDirectory) app.setPath('userData', path.resolve(testDirectory));
const single = testOutput ? true : app.requestSingleInstanceLock();
if (!single) app.quit();
let window: BrowserWindow | undefined;
let preview: BrowserWindow | undefined;
let tray: Tray;
let quitting = false;
let previewTimer: NodeJS.Timeout;
let store: Store;
let receiver: Receiver;
let warning: string | undefined;
let bonjour: Bonjour | undefined;
let downloadUrl: string | undefined;
let downloadServer: http.Server | undefined;
const imageData = (filename: string) => 'data:image/png;base64,' + fs.readFileSync(filename).toString('base64');

async function copyImage(filename: string) {
  const video = path.extname(filename).toLowerCase() === '.mp4';
  if (isMac) return video ? copyMacFiles([filename]) : copyMacImage(filename);
  const {clipboardSequence, verifyClipboard} = await import('./windowsClipboard');
  const uri = pathToFileURL(filename).href;
  const bytes = video ? undefined : fs.readFileSync(filename);
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const previous = clipboardSequence();
      const item = video ? new ClipboardItem({'text/uri-list': uri}) : new ClipboardItem({'image/png': new Blob([new Uint8Array(bytes!)], {type: 'image/png'})});
      await clipboard.write([item]);
      verifyClipboard(filename, previous);
      return;
    }
    catch (error) {if (attempt === 2) throw error; await new Promise(resolve => setTimeout(resolve, 150));}
  }
}
async function copyFiles(filenames: string[]) {
  if (!filenames.length || filenames.length > MAX_BATCH_IMAGES) throw new Error('图集数量无效');
  if (isMac) return copyMacFiles(filenames);
  const {clipboardSequence, verifyClipboardFiles} = await import('./windowsClipboard');
  for (const file of filenames) await fs.promises.access(file);
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const previous = clipboardSequence();
      await clipboard.write([new ClipboardItem({'text/uri-list': filenames.map(file => pathToFileURL(file).href).join('\r\n')})]);
      verifyClipboardFiles(filenames, previous); return;
    } catch (error) {if (attempt === 2) throw error; await new Promise(resolve => setTimeout(resolve, 150));}
  }
}
function options(): Electron.BrowserWindowConstructorOptions {
  return {backgroundColor: '#f7f8fa', show: false, autoHideMenuBar: true,
    webPreferences: {preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: true}};
}
function secure(view: BrowserWindow) {
  view.webContents.setWindowOpenHandler(() => ({action: 'deny'}));
  view.webContents.on('will-navigate', event => event.preventDefault());
  view.webContents.session.setPermissionRequestHandler((_web, _permission, callback) => callback(false));
}
function showWindow() {
  if (!window) {
    window = new BrowserWindow({...options(), width: 1060, height: 760, minWidth: 780, minHeight: 600, title: appName});
    window.on('page-title-updated', event => event.preventDefault());
    secure(window);
    window.on('close', event => {if (!quitting) {event.preventDefault(); window?.hide();}});
    void window.loadFile(path.join(__dirname, 'renderer/index.html'));
    window.once('ready-to-show', () => window?.showInactive());
  } else {window.show(); window.focus();}
}
function changed(item?: Transfer) {
  window?.webContents.send('changed');
  if (!item || testOutput) return;
  if (previewTimer) clearTimeout(previewTimer);
  preview?.close();
  const area = screen.getPrimaryDisplay().workArea;
  preview = new BrowserWindow({...options(), width: 350, height: 144, x: area.x + area.width - 370, y: area.y + area.height - 164,
    frame: false, resizable: false, focusable: false, skipTaskbar: true, alwaysOnTop: true});
  secure(preview);
  void preview.loadFile(path.join(__dirname, 'renderer/index.html'), {query: {preview: item.requestId}});
  preview.once('ready-to-show', () => preview?.showInactive());
  previewTimer = setTimeout(() => {preview?.close(); preview = undefined;}, 4000);
}
function state(): DesktopState {
  return {isMac, version: app.getVersion(), name: store.state.name, deviceId: store.state.deviceId, addresses: addresses(), port: receiver.port,
    fingerprint: store.tls.fingerprint, settings: store.state.settings, warning: warning || store.cleanupWarning, downloadUrl,
    devices: store.state.devices.map(({tokenHash: _token, ...device}) => device),
    transfers: [...store.state.transfers].reverse().filter(item => !item.cacheExpired).map(item => ({...item, thumbnail: item.thumbnailPath && fs.existsSync(item.thumbnailPath) ? imageData(item.thumbnailPath) : undefined}))};
}
function getTransfer(id: unknown) {
  const item = store.state.transfers.find(value => value.requestId === id);
  if (item?.cacheExpired || !item?.imagePath || !fs.existsSync(item.imagePath)) throw new Error('素材缓存已被清理');
  return item;
}
function updateLoginItem(openAtLogin: boolean) {
  if (isMac) {app.setLoginItemSettings({openAtLogin}); return;}
  const legacyPath = path.join(path.dirname(process.execPath), '随手传.exe');
  for (const item of app.getLoginItemSettings({path: legacyPath}).launchItems) {
    if (item.scope === 'user' && path.resolve(item.path).toLowerCase() === legacyPath.toLowerCase()) {
      app.setLoginItemSettings({openAtLogin: false, name: item.name});
    }
  }
  app.setLoginItemSettings({openAtLogin, name: 'CtrlV', args: ['--hidden']});
}
function registerIpc() {
  const handlers: Record<string, (...args: unknown[]) => unknown> = {
    state,
    pair: async () => {
      const invitation = receiver.pairing();
      if (!invitation.addresses.length) throw new Error('未找到可用的局域网地址，请先连接 Wi-Fi 或网线');
      const uri = 'imagebridge://pair?data=' + encodeURIComponent(JSON.stringify(invitation));
      return {uri, qr: await QRCode.toDataURL(uri, {width: 340, margin: 2, errorCorrectionLevel: 'M'}), expiresAt: invitation.expiresAt};
    },
    settings: (value: unknown) => {
      const settings = value as Partial<Settings>;
      if (typeof settings.receiving === 'boolean') store.state.settings.receiving = settings.receiving;
      if (typeof settings.launchAtLogin === 'boolean') {
        store.state.settings.launchAtLogin = settings.launchAtLogin;
        updateLoginItem(settings.launchAtLogin);
      }
      store.save(); updateTray(); changed();
    },
    revoke: (id: unknown) => {store.state.devices = store.state.devices.filter(device => device.clientId !== id); store.save(); changed();},
    copy: async (id: unknown) => {
      const item = getTransfer(id);
      const release = store.pin(item.requestId);
      try {
        if (item.images) await copyFiles(item.images.map(image => image.imagePath)); else await copyImage(item.imagePath!);
        store.state.clipboardRequestId = item.images || item.mime === 'video/mp4' ? item.requestId : undefined;
        Object.assign(item, {status: 'copied', copiedAt: Date.now(), error: undefined});
        store.save(); changed(item);
      } finally {release(); void store.prune().then(() => changed());}
    },
    save: async (id: unknown) => {
      const item = getTransfer(id);
      if (item.images) {
        const result = await dialog.showOpenDialog({title: '选择保存图集的文件夹', properties: ['openDirectory', 'createDirectory']});
        if (result.canceled) return;
        const current = getTransfer(id); const release = store.pin(current.requestId);
        try {for (const image of current.images!) await fs.promises.copyFile(image.imagePath, path.join(result.filePaths[0], path.basename(image.imagePath)));}
        finally {release(); void store.prune().then(() => changed());}
        return;
      }
      const video = item.mime === 'video/mp4';
      const result = await dialog.showSaveDialog({defaultPath: path.join(app.getPath(video ? 'videos' : 'pictures'), appName + '-' + new Date(item.createdAt).toISOString().replace(/[:.]/g, '-') + (video ? '.mp4' : '.png')), filters: [{name: video ? 'MP4 视频' : 'PNG 图片', extensions: [video ? 'mp4' : 'png']}]});
      if (!result.canceled && result.filePath) {
        const current = getTransfer(id); const release = store.pin(current.requestId);
        try {await fs.promises.copyFile(current.imagePath!, result.filePath);} finally {release(); void store.prune().then(() => changed());}
      }
    },
    open: async (id: unknown) => {const result = await shell.openPath(getTransfer(id).imagePath!); if (result) throw new Error(result);},
  };
  for (const [name, handler] of Object.entries(handlers)) ipcMain.handle(name, (event, ...args: unknown[]) => {
    if (![window?.webContents, preview?.webContents].includes(event.sender) || event.senderFrame !== event.sender.mainFrame) throw new Error('请求来源错误');
    return handler(...args);
  });
}
function updateTray() {
  if (!tray) return;
  tray.setToolTip(appName + ' · ' + (store.state.settings.receiving ? '正在接收' : '接收已暂停'));
  tray.setContextMenu(Menu.buildFromTemplate([
    {label: '打开 ' + appName, click: showWindow},
    {label: '接收手机图片', type: 'checkbox', checked: store.state.settings.receiving, click: item => {store.state.settings.receiving = item.checked; store.save(); changed(); updateTray();}},
    {type: 'separator'}, {label: '退出', click: () => {quitting = true; app.quit();}},
  ]));
}
async function startDownload() {
  const apk = app.isPackaged ? path.join(process.resourcesPath, 'CtrlC.apk') : path.resolve(__dirname, '../../../release/android/CtrlC.apk');
  if (!fs.existsSync(apk)) return;
  const key = randomBytes(16).toString('hex');
  downloadServer = http.createServer((req, res) => {
    if (!isPrivate(req.socket.remoteAddress ?? '') || req.url !== '/' + key + '/CtrlC.apk' || req.method !== 'GET') {res.writeHead(404); res.end(); return;}
    res.writeHead(200, {'Content-Type': 'application/vnd.android.package-archive', 'Content-Disposition': 'attachment; filename="CtrlC.apk"', 'Content-Length': fs.statSync(apk).size});
    fs.createReadStream(apk).pipe(res);
  });
  await new Promise<void>(resolve => {downloadServer!.once('error', () => resolve()); downloadServer!.listen(43822, '0.0.0.0', resolve);});
  const address = addresses()[0];
  if (address && downloadServer.listening) downloadUrl = `http://${address}:43822/${key}/CtrlC.apk`;
}
async function start() {
  if (!safeStorage.isEncryptionAvailable()) throw new Error('系统凭据加密不可用，无法安全保存配对信息');
  store = new Store(app.getPath('userData'), {seal: value => safeStorage.encryptString(value).toString('base64'), open: value => safeStorage.decryptString(Buffer.from(value, 'base64'))});
  if (!isMac && app.isPackaged && !testDirectory && !testOutput) updateLoginItem(store.state.settings.launchAtLogin);
  receiver = new Receiver(store, copyImage, changed, copyFiles);
  try {await receiver.start(testOutput ? 0 : 43821);} catch (error) {if (testOutput) throw error; await receiver.start(0); warning = '默认端口被占用，已使用备用端口；请刷新二维码。';}
  if (testOutput) {
    const {runSelfTest} = await import('./selftest');
    const report = await runSelfTest(receiver, copyImage);
    fs.writeFileSync(testOutput, JSON.stringify(report, null, 2));
    quitting = true; app.quit(); return;
  }
  try {
    bonjour = new Bonjour();
    bonjour.publish({name: 'ImageBridge-' + store.state.deviceId.slice(0, 8), type: 'imagebridge', port: receiver.port, txt: {id: store.state.deviceId, name: store.state.name, v: '1'}}).on('error', () => {warning = '自动发现暂不可用，仍可扫码连接'; changed();});
  } catch {warning = '自动发现暂不可用，仍可扫码连接';}
  registerIpc();
  const icon = await import('sharp').then(module => module.default(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" rx="8" fill="#2563eb"/><rect x="7" y="9" width="18" height="15" rx="3" fill="white"/><circle cx="16" cy="16" r="4" fill="#2563eb"/><rect x="11" y="6" width="10" height="5" rx="2" fill="white"/></svg>')).png().toBuffer());
  tray = new Tray(nativeImage.createFromBuffer(icon));
  tray.on('double-click', showWindow); updateTray();
  if (!isMac) await startDownload();
  if (!process.argv.includes('--hidden')) showWindow();
  setInterval(() => {void store.prune().then(() => changed());}, 5000).unref();
}
app.on('second-instance', showWindow);
app.on('activate', () => {if (receiver) showWindow();});
app.on('window-all-closed', () => {});
app.on('before-quit', () => {quitting = true; bonjour?.destroy(); downloadServer?.close();});
if (single) void app.whenReady().then(start).catch(error => {
  const message = error instanceof Error ? error.message : String(error);
  fs.mkdirSync(app.getPath('userData'), {recursive: true});
  fs.appendFileSync(path.join(app.getPath('userData'), 'error.log'), new Date().toISOString() + ' ' + message + '\n');
  if (testOutput) fs.writeFileSync(testOutput, JSON.stringify({error: message}));
  else dialog.showErrorBox(appName + ' 启动失败', message);
  app.exit(1);
});
