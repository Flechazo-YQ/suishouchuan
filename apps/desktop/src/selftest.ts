import {app, clipboard, ClipboardItem} from 'electron';
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import sharp from 'sharp';
import {Receiver} from './receiver';
import {sha256} from './store';
import {clipboardFiles, clipboardSequence, verifyClipboard} from './windowsClipboard';

export async function runSelfTest(receiver: Receiver, copy: (filename: string) => Promise<void>) {
  const original = await clipboard.read();
  const saved = await Promise.all(original.map(async item => {
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
    const before = clipboardSequence();
    let staleWriteRejected = false;
    try {verifyClipboard('unchanged.png', before);} catch {staleWriteRejected = true;}
    const invitation = receiver.pairing();
    const paired = await request('/v1/pair', Buffer.from(JSON.stringify({code: invitation.code, clientId: randomUUID(), name: '本机验收'})));
    const token = String(paired.body.token);
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
    const fileClipboard = clipboardFiles().includes(videoPath);
    const batchManifest = Buffer.from(JSON.stringify({images: Array.from({length: 10}, () => ({bytes: image.length, mime: 'image/png', sha256: sha256(image)}))}));
    const batchPrefix = Buffer.alloc(4); batchPrefix.writeUInt32BE(batchManifest.length);
    const batchId = randomUUID();
    const batchResult = await request('/v1/batches', Buffer.concat([batchPrefix, batchManifest, ...Array.from({length: 10}, () => image)]), token,
      {'Content-Type': 'application/x-imagebridge-batch', 'X-Request-Id': batchId, 'X-Content-SHA256': sha256(batchManifest)});
    const batchFiles = clipboardFiles();
    const batchClipboard = batchResult.body.status === 'copied' && batchFiles.length === 10 && batchFiles.every((file, index) => path.basename(file) === `${batchId}-${String(index + 1).padStart(2, '0')}.png`);
    const report = {pairing: paired.status === 201, transfer: result.body.status === 'copied', clipboard: {width: meta.width, height: meta.height, alpha: meta.hasAlpha},
      duplicateDidNotOverwrite: repeated.body.status === 'copied' && preserved === 'imagebridge-idempotency-marker', unauthorizedRejected: unauthorized.status === 401, fileClipboard, batchClipboard, staleWriteRejected, elapsedMs: elapsed, version: app.getVersion()};
    if (!report.pairing || !report.transfer || !report.duplicateDidNotOverwrite || !report.unauthorizedRejected || !fileClipboard || !batchClipboard || !staleWriteRejected || meta.width !== 720) throw new Error(JSON.stringify(report));
    return report;
  } finally {agent.destroy(); if (saved.length) await clipboard.write(saved); else await clipboard.clear();}
}
