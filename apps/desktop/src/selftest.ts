import {app, clipboard, ClipboardItem} from 'electron';
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import sharp from 'sharp';
import {Receiver} from './receiver';
import {sha256} from './store';
import {readMacClipboardFiles} from './macPlatform';

export async function runSelfTest(receiver: Receiver, copy: (filename: string) => Promise<void>) {
  const windows = process.platform === 'win32' ? await import('./windowsClipboard') : undefined;
  const readFiles = windows ? windows.clipboardFiles : readMacClipboardFiles;
  const original = await clipboard.read();
  const saved = await Promise.all(original.filter(item => item.types.length > 0).map(async item => {
    const entries = await Promise.all(item.types.map(async type => [type, await item.getType(type)] as const));
    return new ClipboardItem(Object.fromEntries(entries));
  }));
  const agent = new https.Agent({rejectUnauthorized: false});
  async function request(route: string, body?: Buffer, token?: string, extra: Record<string, string> = {}) {
    return new Promise<{status: number; body: Record<string, unknown>}>((resolve, reject) => {
      const req = https.request({hostname: '127.0.0.1', port: receiver.port, path: route, method: body ? 'POST' : 'GET', agent,
        headers: {...(body ? {'Content-Length': String(body.length)} : {}), ...(token ? {Authorization: 'Bearer ' + token} : {}), ...extra}}, res => {
        const chunks: Buffer[] = []; res.on('data', chunk => chunks.push(Buffer.from(chunk))); res.on('end', () => resolve({status: res.statusCode!, body: JSON.parse(Buffer.concat(chunks).toString()) as Record<string, unknown>}));
      });
      req.on('socket', socket => {
        const tls = socket as import('node:tls').TLSSocket;
        tls.once('secureConnect', () => {if (sha256(tls.getPeerCertificate().raw) !== receiver.store.tls.fingerprint) req.destroy(new Error('测试服务证书不匹配'));});
      });
      req.on('error', reject); req.end(body);
    });
  }
  try {
    let staleWriteRejected = false;
    let missingFileRejected = false;
    if (windows) {
      const before = windows.clipboardSequence();
      try {windows.verifyClipboard('unchanged.png', before);} catch {staleWriteRejected = true;}
    } else {
      try {await copy(path.join(receiver.store.cache, 'missing.png'));} catch {missingFileRejected = true;}
    }
    const invitation = receiver.pairing();
    const paired = await request('/v1/pair', Buffer.from(JSON.stringify({code: invitation.code, clientId: randomUUID(), name: '本机验收'})));
    const token = String(paired.body.token);
    const probe = await request('/v1/presence', undefined, token);
    const rejectedProbe = await request('/v1/presence');
    const pairedDevice = receiver.store.state.devices.find(device => device.tokenHash === sha256(token));
    const connectionVerified = probe.status === 200 && probe.body.connected === true && rejectedProbe.status === 401 &&
      !!pairedDevice && receiver.isConnected(pairedDevice) && !receiver.isConnected(pairedDevice, Date.now() + 16 * 60_000);
    const image = await sharp({create: {width: 720, height: 480, channels: 4, background: {r: 37, g: 99, b: 235, alpha: .65}}}).png().toBuffer();
    const id = randomUUID();
    const headers = {'Content-Type': 'image/png', 'X-Request-Id': id, 'X-Content-SHA256': sha256(image)};
    const started = performance.now();
    const result = await request('/v1/images', image, token, headers);
    const elapsed = Math.round(performance.now() - started);
    const items = await clipboard.read();
    const png = items.find(item => item.types.includes('image/png'));
    if (!png) throw new Error('系统剪贴板缺少图片格式');
    const blob = await png.getType('image/png');
    const meta = await sharp(Buffer.from(await blob.arrayBuffer())).metadata();
    await clipboard.write([new ClipboardItem({'text/plain': 'imagebridge-idempotency-marker'})]);
    const repeated = await request('/v1/images', image, token, headers);
    const preserved = await clipboard.readText();
    const unauthorized = await request('/v1/images', image, 'invalid', headers);
    const videoPath = path.join(receiver.store.cache, 'clipboard-file-test.mp4');
    fs.writeFileSync(videoPath, 'Clipboard file reference test');
    await copy(videoPath);
    const filesAfterVideo = await readFiles();
    const fileClipboard = filesAfterVideo.includes(fs.realpathSync(videoPath)) || filesAfterVideo.includes(videoPath);
    const capabilities = await request('/v1/capabilities', undefined, token);
    const batchImage = await sharp(image).resize(40).png().toBuffer();
    const batchImages = Array<Buffer>(99).fill(batchImage);
    const batchManifest = Buffer.from(JSON.stringify({images: batchImages.map(bytes => ({bytes: bytes.length, mime: 'image/png', sha256: sha256(bytes)}))}));
    const batchPrefix = Buffer.alloc(4); batchPrefix.writeUInt32BE(batchManifest.length);
    const batchId = randomUUID();
    const batchResult = await request('/v1/batches', Buffer.concat([batchPrefix, batchManifest, ...batchImages]), token,
      {'Content-Type': 'application/x-imagebridge-batch', 'X-Request-Id': batchId, 'X-Content-SHA256': sha256(batchManifest)});
    const clipboardEntries = await readFiles();
    const folder = !windows && clipboardEntries.length === 1 && path.basename(clipboardEntries[0]) === 'Batch-' + batchId
      ? clipboardEntries[0] : undefined;
    const batchFiles = folder ? fs.readdirSync(folder).sort() : clipboardEntries;
    const batchClipboard = (Boolean(windows) || Boolean(folder)) && capabilities.body.maxBatchImages === batchImages.length && batchResult.body.status === 'copied' &&
      batchFiles.length === batchImages.length && batchFiles.every((file, index) => path.basename(file) === `${batchId}-${String(index + 1).padStart(2, '0')}.png`);
    const report = {pairing: paired.status === 201, connectionVerified, transfer: result.body.status === 'copied', clipboard: {width: meta.width, height: meta.height, alpha: meta.hasAlpha},
      duplicateDidNotOverwrite: repeated.body.status === 'copied' && preserved === 'imagebridge-idempotency-marker', unauthorizedRejected: unauthorized.status === 401, fileClipboard, batchClipboard, batchFileCount: batchFiles.length, batchClipboardMode: folder ? 'folder' : 'files', batchStatus: batchResult.body.status, batchError: batchResult.body.error, staleWriteRejected, missingFileRejected, elapsedMs: elapsed, version: app.getVersion()};
    const clipboardGuardPassed = windows ? staleWriteRejected : missingFileRejected;
    if (!report.pairing || !connectionVerified || !report.transfer || !report.duplicateDidNotOverwrite || !report.unauthorizedRejected || !fileClipboard || !batchClipboard || !clipboardGuardPassed || meta.width !== 720) throw new Error(JSON.stringify(report));
    return report;
  } finally {agent.destroy(); if (saved.length) await clipboard.write(saved); else await clipboard.clear();}
}
