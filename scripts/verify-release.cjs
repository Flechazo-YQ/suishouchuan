const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {extractFile} = require('../apps/desktop/node_modules/@electron/asar');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const desktop = JSON.parse(read('apps/desktop/package.json'));
const mobile = JSON.parse(read('apps/mobile/package.json'));
const archive = path.join(root, 'release/windows/win-unpacked/resources/app.asar');
const packaged = JSON.parse(extractFile(archive, 'package.json'));
assert.equal(packaged.version, desktop.version);
assert.equal(hash(extractFile(archive, 'dist/main.cjs')), hash(read('apps/desktop/dist/main.cjs')));
const apkHash = hash(read('release/android/CtrlV.apk'));
assert.equal(hash(read('release/windows/win-unpacked/resources/CtrlV.apk')), apkHash);
for (const name of ['ffprobe.exe', 'FFmpeg-LICENSE.txt', 'FFmpeg-README.txt']) {
  assert.equal(hash(read('release/windows/win-unpacked/resources/' + name)), hash(read('apps/desktop/resources/' + name)));
}
const nativeClipboard = 'node_modules/@koromix/koffi-win32-x64/win32_x64/koffi.node';
assert.equal(hash(read('release/windows/win-unpacked/resources/app.asar.unpacked/' + nativeClipboard)), hash(read('apps/desktop/' + nativeClipboard)));
const installer = 'release/windows/CtrlV-Setup-' + desktop.version + '.exe';
const report = {
  generatedAt: new Date().toISOString(),
  desktopVersion: desktop.version,
  androidVersion: mobile.version,
  androidSha256: apkHash,
  installerSha256: hash(read(installer)),
  packagedCodeMatchesBuild: true,
  bundledApkMatchesRelease: true,
  bundledMediaToolsAndNoticesMatch: true,
  bundledNativeClipboardMatches: true,
  runtimeVerified: false,
};
fs.writeFileSync(path.join(root, 'release/manifest.json'), JSON.stringify(report, null, 2));
process.stdout.write(JSON.stringify(report, null, 2) + '\n');
