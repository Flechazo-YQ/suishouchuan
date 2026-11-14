import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {randomUUID, createHash, randomBytes} from 'node:crypto';
import forge from 'node-forge';
import type {Device, Settings, Transfer} from './types';

interface State {
  deviceId: string; name: string; settings: Settings; devices: Device[]; transfers: Transfer[]; clipboardRequestId?: string;
}
export interface SecretCodec {seal(value: string): string; open(value: string): string}
export const sha256 = (data: string | Buffer) => createHash('sha256').update(data).digest('hex');
export const MAX_BYTES = 32 * 1024 * 1024;
export const MAX_PIXELS = 64_000_000;
export const MAX_CACHE_BYTES = 100_000_000;
export class Store {
  readonly directory: string;
  readonly cache: string;
  state: State;
  readonly tls: {key: string; cert: string; fingerprint: string};
  private protectedIds = new Map<string, number>();
  private evicting = new Set<string>();
  private cleanup: Promise<void> = Promise.resolve();
  private orphanedFiles = new Set<string>();
  cleanupWarning?: string;
  constructor(directory: string, codec: SecretCodec) {
    this.directory = directory;
    this.cache = path.join(directory, 'images');
    fs.mkdirSync(this.cache, {recursive: true});
    const filename = path.join(directory, 'state.json');
    this.state = fs.existsSync(filename) ? JSON.parse(fs.readFileSync(filename, 'utf8')) as State : {
      deviceId: randomUUID(), name: os.hostname(), settings: {receiving: true, launchAtLogin: false}, devices: [], transfers: [],
    };
    const identity = path.join(directory, 'identity.json');
    if (fs.existsSync(identity)) {
      const saved = JSON.parse(fs.readFileSync(identity, 'utf8')) as {key: string; cert: string};
      this.tls = {key: codec.open(saved.key), cert: saved.cert, fingerprint: ''};
    } else {
      const keys = forge.pki.rsa.generateKeyPair(2048);
      const cert = forge.pki.createCertificate();
      cert.publicKey = keys.publicKey;
      cert.serialNumber = '01' + randomBytes(15).toString('hex');
      cert.validity.notBefore = new Date(Date.now() - 86_400_000);
      cert.validity.notAfter = new Date(Date.now() + 5 * 365 * 86_400_000);
      const attrs = [{name: 'commonName', value: this.state.deviceId}];
      cert.setSubject(attrs); cert.setIssuer(attrs);
      cert.setExtensions([{name: 'basicConstraints', cA: false}, {name: 'keyUsage', digitalSignature: true, keyEncipherment: true}, {name: 'extKeyUsage', serverAuth: true}]);
      cert.sign(keys.privateKey, forge.md.sha256.create());
      this.tls = {key: forge.pki.privateKeyToPem(keys.privateKey), cert: forge.pki.certificateToPem(cert), fingerprint: ''};
      fs.writeFileSync(identity, JSON.stringify({key: codec.seal(this.tls.key), cert: this.tls.cert}), {mode: 0o600});
    }
    this.tls.fingerprint = sha256(Buffer.from(forge.asn1.toDer(forge.pki.certificateToAsn1(forge.pki.certificateFromPem(this.tls.cert))).getBytes(), 'binary'));
    for (const transfer of this.state.transfers) {
      if (transfer.status === 'receiving') { transfer.status = 'failed'; transfer.error = '接收中断，请重新发送'; }
      transfer.cachedBytes = this.files(transfer).reduce((sum, file) => sum + (fs.existsSync(file) ? fs.statSync(file).size : 0), 0);
    }
    const referenced = new Set(this.state.transfers.flatMap(item => this.files(item)));
    for (const name of fs.readdirSync(this.cache)) {
      const file = path.join(this.cache, name);
      if (!referenced.has(file) && /\.(png|jpg|mp4|part)$/.test(name)) this.orphanedFiles.add(file);
    }
    this.save();
  }
  save() {
    const target = path.join(this.directory, 'state.json');
    fs.writeFileSync(target + '.tmp', JSON.stringify(this.state, null, 2), {mode: 0o600});
    fs.renameSync(target + '.tmp', target);
  }
  private files(item: Transfer) {
    return [...new Set([item.imagePath, item.thumbnailPath, ...(item.images ?? []).flatMap(image => [image.imagePath, image.thumbnailPath])])].filter((file): file is string => !!file && path.dirname(file) === this.cache);
  }
  pin(id: string) {
    if (this.evicting.has(id)) throw new Error('素材缓存已被清理');
    this.protectedIds.set(id, (this.protectedIds.get(id) ?? 0) + 1);
    return () => {
      const count = (this.protectedIds.get(id) ?? 1) - 1;
      if (count) this.protectedIds.set(id, count); else this.protectedIds.delete(id);
    };
  }
  async measure(item: Transfer) {
    const sizes = await Promise.all(this.files(item).map(async file => (await fs.promises.stat(file)).size));
    const bytes = sizes.reduce((sum, value) => sum + value, 0);
    if (bytes > MAX_CACHE_BYTES) throw new Error('单份素材及缩略图超过 100 MB 缓存上限，请缩小后重试');
    item.cachedBytes = bytes; item.cacheExpired = false;
  }
  async discard(item: Transfer) {
    for (const file of this.files(item)) await fs.promises.rm(file, {force: true, maxRetries: 2, retryDelay: 50});
    item.imagePath = undefined; item.thumbnailPath = undefined; item.images = undefined; item.cachedBytes = 0; item.cacheExpired = true;
  }
  prune() {
    // File deletion runs after acknowledgement and never synchronously blocks image decoding or upload.
    this.cleanup = this.cleanup.then(async () => {
      for (const file of this.orphanedFiles) {await fs.promises.rm(file, {force: true, maxRetries: 2, retryDelay: 50}); this.orphanedFiles.delete(file);}
      let total = this.state.transfers.reduce((sum, item) => sum + (item.cachedBytes ?? 0), 0);
      const oldest = this.state.transfers.filter(item => item.imagePath).sort((a, b) => a.createdAt - b.createdAt);
      const newest = oldest.at(-1);
      for (const item of oldest) {
        if (total <= MAX_CACHE_BYTES) break;
        if ((item === newest && (item.cachedBytes ?? 0) <= MAX_CACHE_BYTES) || item.requestId === this.state.clipboardRequestId || item.status === 'receiving' || this.protectedIds.has(item.requestId)) continue;
        const bytes = item.cachedBytes ?? 0;
        this.evicting.add(item.requestId);
        try {await this.discard(item); total -= bytes;} finally {this.evicting.delete(item.requestId);}
      }
      // Retain lightweight receipts so retries of evicted files cannot replace the clipboard again.
      const receipts = new Set(this.state.transfers.filter(item => item.cacheExpired).slice(-2048).map(item => item.requestId));
      this.state.transfers = this.state.transfers.filter(item => !item.cacheExpired || receipts.has(item.requestId));
      this.cleanupWarning = undefined;
      this.save();
    }).catch(() => {this.cleanupWarning = '旧缓存暂时被占用，将在后台继续清理';});
    return this.cleanup;
  }
}
