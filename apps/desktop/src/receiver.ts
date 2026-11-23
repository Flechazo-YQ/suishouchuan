import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {createHash, randomBytes, timingSafeEqual} from 'node:crypto';
import type {IncomingMessage, ServerResponse} from 'node:http';
import sharp from 'sharp';
import {Store, sha256, MAX_BYTES, MAX_PIXELS, MAX_CACHE_BYTES} from './store';
import type {Device, Pairing, Transfer} from './types';
import {inspectVideo, videoThumbnail, MAX_VIDEO_BYTES} from './media';
import {MAX_BATCH_IMAGES, receiveBatch} from './batch';

// libvips may retain JPEG file handles on Windows after decoding.
sharp.cache(false);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HASH = /^[0-9a-f]{64}$/;
const DEVICE_PRESENCE_MS = 15 * 60_000 + 30_000;
const equal = (a: string, b: string) => a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));
export const isPrivate = (value: string) => /^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(value.replace('::ffff:', ''));
export function addresses() {
  return Object.entries(os.networkInterfaces())
    .filter(([name]) => !/vmware|vethernet|virtual|docker|loopback/i.test(name))
    .flatMap(([, items]) => items ?? []).filter(item => item.family === 'IPv4' && !item.internal && isPrivate(item.address)).map(item => item.address);
}
class RequestError extends Error { constructor(readonly status: number, message: string) {super(message);} }
export function publicTransfer(item: Transfer) {
  const {imagePath: _image, thumbnailPath: _thumb, images: _images, clientId: _client, ...result} = item;
  return result;
}
export class Receiver {
  private server?: https.Server;
  private invitation?: Pairing;
  private active = new Set<string>();
  private cleaningRequests = new Set<string>();
  private requests = new Set<Promise<void>>();
  private receivedOrder = 0;
  private clipboardQueue: Promise<void> = Promise.resolve();
  private attempts = new Map<string, {time: number; count: number}>();
  private presence = new Map<string, number>();
  private presenceTimer?: NodeJS.Timeout;
  port = 0;
  constructor(readonly store: Store, private readonly copy: (imagePath: string) => Promise<void>, private readonly changed: (item?: Transfer) => void, private readonly copyMany?: (paths: string[]) => Promise<void>) {}
  async start(port = 43821) {
    this.server = https.createServer({key: this.store.tls.key, cert: this.store.tls.cert, minVersion: 'TLSv1.2'}, (req, res) => {
      const pending = this.handle(req, res).catch(error => {
        if (!res.headersSent) this.reply(res, error instanceof RequestError ? error.status : 500, {error: error instanceof RequestError ? error.message : '电脑处理失败，请重试'});
        else res.end();
      });
      this.requests.add(pending);
      void pending.finally(() => this.requests.delete(pending));
    });
    this.server.requestTimeout = 120_000;
    this.server.headersTimeout = 10_000;
    await new Promise<void>((resolve, reject) => {
      this.server!.once('error', reject);
      this.server!.listen(port, '0.0.0.0', () => { this.server!.removeListener('error', reject); resolve(); });
    });
    const address = this.server.address();
    if (!address || typeof address === 'string') throw new Error('接收服务启动失败');
    this.port = address.port;
    void this.store.prune();
  }
  async stop() {
    clearTimeout(this.presenceTimer);
    this.presence.clear();
    await new Promise<void>(resolve => this.server?.close(() => resolve()) ?? resolve());
    await Promise.allSettled([...this.requests]);
    await this.store.prune();
  }
  isConnected(device: Device, now = Date.now()) {
    return (this.presence.get(device.tokenHash) ?? 0) > now;
  }
  refreshPresence(networkChanged = false) {
    const previous = this.presence.size;
    const now = Date.now();
    for (const [tokenHash, expires] of this.presence) {
      if (networkChanged || expires <= now || !this.store.state.devices.some(device => device.tokenHash === tokenHash)) this.presence.delete(tokenHash);
    }
    this.schedulePresenceExpiry();
    if (this.presence.size !== previous) this.changed();
  }
  private trackPresence(device: Device) {
    const online = this.isConnected(device);
    this.presence.set(device.tokenHash, Date.now() + DEVICE_PRESENCE_MS);
    this.schedulePresenceExpiry();
    if (!online) this.changed();
  }
  private schedulePresenceExpiry() {
    clearTimeout(this.presenceTimer);
    const next = Math.min(...this.presence.values());
    if (Number.isFinite(next)) this.presenceTimer = setTimeout(() => this.refreshPresence(), Math.max(1, next - Date.now())).unref();
  }
  pairing(): Pairing {
    this.invitation = {v: 1, deviceId: this.store.state.deviceId, name: this.store.state.name, addresses: addresses(), port: this.port,
      fingerprint: this.store.tls.fingerprint, code: randomBytes(24).toString('base64url'), expiresAt: Date.now() + 5 * 60_000};
    return this.invitation;
  }
  private reply(res: ServerResponse, status: number, body: unknown) {
    res.writeHead(status, {'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'});
    res.end(JSON.stringify(body));
  }
  private authenticate(req: IncomingMessage): Device {
    const token = req.headers.authorization?.replace(/^Bearer /, '') ?? '';
    const hash = sha256(token);
    const device = this.store.state.devices.find(item => equal(item.tokenHash, hash));
    if (!device) throw new RequestError(401, '配对已失效，请在电脑端重新扫码配对');
    return device;
  }
  private async pair(req: IncomingMessage, res: ServerResponse) {
    const remote = req.socket.remoteAddress ?? '';
    const previous = this.attempts.get(remote);
    const attempt = previous && previous.time > Date.now() - 60_000 ? previous : {time: Date.now(), count: 0};
    if (++attempt.count > 10) throw new RequestError(429, '配对尝试过多，请稍后重试');
    if (this.attempts.size > 100) this.attempts.clear();
    this.attempts.set(remote, attempt);
    const buffers: Buffer[] = []; let bytes = 0;
    for await (const chunk of req) {
      const data = Buffer.from(chunk); bytes += data.length;
      if (bytes > 4096) throw new RequestError(413, '配对数据过大');
      buffers.push(data);
    }
    let body: {code?: string; clientId?: string; name?: string};
    try {body = JSON.parse(Buffer.concat(buffers).toString('utf8'));} catch {throw new RequestError(400, '配对数据不正确');}
    if (!body || typeof body.code !== 'string' || typeof body.clientId !== 'string' || !UUID.test(body.clientId) || typeof body.name !== 'string' || !body.name.trim() || body.name.length > 80) throw new RequestError(400, '配对信息不完整');
    if (!this.invitation || this.invitation.expiresAt < Date.now() || !equal(this.invitation.code, body.code)) throw new RequestError(403, '二维码已失效，请在电脑端刷新');
    this.invitation = undefined;
    const token = randomBytes(32).toString('base64url');
    this.store.state.devices = this.store.state.devices.filter(item => item.clientId !== body.clientId);
    const device = {clientId: body.clientId, name: body.name.trim(), pairedAt: Date.now(), tokenHash: sha256(token)};
    this.store.state.devices.push(device);
    this.store.save(); this.trackPresence(device);
    this.reply(res, 201, {deviceId: this.store.state.deviceId, name: this.store.state.name, token});
  }
  private async handle(req: IncomingMessage, res: ServerResponse) {
    if (!isPrivate(req.socket.remoteAddress ?? '') || req.headers.origin) throw new RequestError(403, '只接受局域网客户端请求');
    if (req.url === '/v1/pair' && req.method === 'POST') return this.pair(req, res);
    const device = this.authenticate(req);
    this.trackPresence(device);
    if (req.url === '/v1/presence' && req.method === 'GET') return this.reply(res, 200, {connected: true});
    if (req.url === '/v1/capabilities' && req.method === 'GET') {
      return this.reply(res, 200, {maxBatchImages: this.copyMany ? MAX_BATCH_IMAGES : 1});
    }
    const statusMatch = req.url?.match(/^\/v1\/transfers\/([a-f0-9-]+)$/i);
    if (req.method === 'GET' && statusMatch) {
      const item = this.store.state.transfers.find(value => value.requestId === statusMatch[1] && value.clientId === device.clientId);
      if (!item) throw new RequestError(404, '未找到发送记录，可以重试');
      return this.reply(res, 200, publicTransfer(item));
    }
    const videoUpload = req.url === '/v1/videos';
    const batchUpload = req.url === '/v1/batches';
    if ((!videoUpload && !batchUpload && req.url !== '/v1/images') || req.method !== 'POST') throw new RequestError(404, '接口不存在');
    if (!this.store.state.settings.receiving) throw new RequestError(503, '电脑已暂停接收，请在托盘中恢复');
    const id = req.headers['x-request-id']; const expectedHash = req.headers['x-content-sha256'];
    if (typeof id !== 'string' || !UUID.test(id) || typeof expectedHash !== 'string' || !HASH.test(expectedHash)) throw new RequestError(400, '发送请求格式错误');
    const existing = this.store.state.transfers.find(item => item.requestId === id);
    if (existing && (existing.clientId !== device.clientId || existing.sha256 !== expectedHash)) throw new RequestError(409, '请求编号与文件不匹配');
    if (existing?.status === 'copied' || existing?.status === 'receiving') {req.resume(); return this.reply(res, 200, publicTransfer(existing));}
    if (existing?.status === 'received' && existing.imagePath) {req.resume(); await this.copyTransfer(existing); void this.store.prune().then(() => this.changed()); return this.reply(res, 200, publicTransfer(existing));}
    if (this.cleaningRequests.has(id) || this.active.has(device.clientId) || this.active.size >= 2) throw new RequestError(429, '上一份文件仍在处理，请稍后重试');
    if (!(batchUpload ? ['application/x-imagebridge-batch'] : videoUpload ? ['video/mp4'] : ['image/png', 'image/jpeg']).includes(req.headers['content-type'] ?? '')) throw new RequestError(415, '文件类型不支持');
    const byteLimit = batchUpload ? 100_016_388 : videoUpload ? MAX_VIDEO_BYTES : MAX_BYTES;
    const sizeMessage = batchUpload ? '整组上限为 100 MB，请拆分发送' : videoUpload ? '视频上限为 100 MB' : '图片上限为 32 MB';
    const contentLength = Number(req.headers['content-length']);
    if (!Number.isFinite(contentLength) || contentLength <= 0 || contentLength > byteLimit) throw new RequestError(413, sizeMessage);
    this.active.add(device.clientId);
    const release = this.store.pin(id);
    const item: Transfer = existing ?? {requestId: id, clientId: device.clientId, clientName: device.name, sha256: expectedHash, status: 'receiving', bytes: 0, createdAt: Date.now()};
    Object.assign(item, {status: 'receiving', error: undefined});
    if (!existing) this.store.state.transfers.push(item);
    this.store.save();
    // AVFoundation selects its file parser from the staged file's extension.
    const partial = path.join(this.store.cache, id + (videoUpload && process.platform === 'darwin' ? '.part.mp4' : '.part'));
    const started = performance.now();
    try {
      if (batchUpload) {
        if (!this.copyMany) throw new RequestError(501, '电脑版本不支持图集，请更新');
        const batch = await receiveBatch(req, this.store.cache, id, expectedHash);
        Object.assign(item, batch, {imageCount: batch.images.length, imagePath: batch.images[0].imagePath, thumbnailPath: batch.images[0].thumbnailPath, mime: batch.images[0].mime, status: 'received', cacheExpired: false});
      } else {
      const file = await fs.promises.open(partial, 'w');
      const hash = createHash('sha256'); let size = 0;
      try {
        for await (const chunk of req) {
          const data = Buffer.from(chunk); size += data.length;
          if (size > byteLimit) throw new RequestError(413, sizeMessage);
          hash.update(data); await file.write(data);
        }
      } finally {await file.close();}
      if (size !== contentLength || hash.digest('hex') !== expectedHash) throw new RequestError(422, '文件传输不完整，请重新发送');
      if (videoUpload) {
        const metadata = await inspectVideo(partial).catch(error => {throw new RequestError(415, error instanceof Error ? error.message : '无法读取视频');});
        item.imagePath = path.join(this.store.cache, id + '.mp4');
        item.thumbnailPath = path.join(this.store.cache, id + '-thumb.png');
        await fs.promises.rename(partial, item.imagePath);
        await videoThumbnail(item.thumbnailPath, metadata.durationMs);
        Object.assign(item, metadata, {mime: 'video/mp4', bytes: size, status: 'received'});
      } else {
        const meta = await sharp(partial, {limitInputPixels: MAX_PIXELS}).metadata();
        if (!meta.width || !meta.height || meta.width * meta.height > MAX_PIXELS || !['png', 'jpeg'].includes(meta.format) || (meta.pages ?? 1) > 1) throw new RequestError(415, '仅支持 6400 万像素以内的静态图片');
        item.imagePath = path.join(this.store.cache, id + '.png');
        item.thumbnailPath = path.join(this.store.cache, id + '-thumb.png');
        const pipeline = sharp(partial, {limitInputPixels: MAX_PIXELS}).rotate().toColourspace('srgb');
        const output = await pipeline.png().toFile(item.imagePath);
        await sharp(item.imagePath).resize({width: 380, height: 260, fit: 'inside', withoutEnlargement: true}).png().toFile(item.thumbnailPath);
        Object.assign(item, {mime: 'image/png', bytes: size, width: output.width, height: output.height, status: 'received'});
      }
      }
      await this.store.measure(item).catch(error => {throw new RequestError(413, error instanceof Error ? error.message : '素材超过缓存容量');});
      // Completion order also matches the serialized clipboard queue when phones upload concurrently.
      this.receivedOrder = Math.max(Date.now(), this.receivedOrder + 1);
      item.createdAt = this.receivedOrder;
      this.store.save();
      await this.copyTransfer(item);
      if (item.status !== 'copied' && (batchUpload || this.store.state.transfers.reduce((sum, transfer) => sum + (transfer.cachedBytes ?? 0), 0) > MAX_CACHE_BYTES)) {
        await this.store.discard(item); item.status = 'failed';
      }
      item.elapsedMs = Math.round(performance.now() - started);
      this.reply(res, 200, publicTransfer(item));
    } catch (error) {
      item.status = 'failed'; item.error = error instanceof RequestError || (batchUpload && error instanceof Error) ? error.message : '无法处理文件，请检查格式后重试';
      this.reply(res, error instanceof RequestError ? error.status : 422, publicTransfer(item));
    } finally {
      this.active.delete(device.clientId);
      if (item.status === 'failed') this.cleaningRequests.add(id);
      await fs.promises.rm(partial, {force: true, maxRetries: 3, retryDelay: 50}).catch(() => {});
      if (item.status === 'failed') await this.store.discard(item).catch(() => {});
      release();
      this.cleaningRequests.delete(id);
      void this.store.prune().then(() => this.changed());
      this.changed();
    }
  }
  async copyTransfer(item: Transfer) {
    const operation = async () => {
      if (item.status === 'copied') return;
      if (!this.store.state.devices.some(device => device.clientId === item.clientId)) {item.status = 'failed'; item.error = '设备配对已撤销'; return;}
      if (!this.store.state.settings.receiving) {item.status = 'received'; item.error = '已接收，电脑已暂停复制'; return;}
      const release = this.store.pin(item.requestId);
      try {
        if (item.images) await this.copyMany!(item.images.map(image => image.imagePath)); else await this.copy(item.imagePath!);
        this.store.state.clipboardRequestId = item.images || item.mime === 'video/mp4' ? item.requestId : undefined;
        item.status = 'copied'; item.copiedAt = Date.now(); item.error = undefined;
        this.changed(item);
      } catch {
        item.status = 'received'; item.error = '文件已接收，但剪贴板尚未写入；请点击重试或在电脑端重新复制';
      } finally {release();}
      this.store.save();
    };
    this.clipboardQueue = this.clipboardQueue.then(operation, operation);
    await this.clipboardQueue;
  }
}
