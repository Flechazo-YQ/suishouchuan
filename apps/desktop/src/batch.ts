import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import type {IncomingMessage} from 'node:http';
import sharp from 'sharp';
import {batchDirectory, MAX_BYTES, MAX_CACHE_BYTES, MAX_PIXELS, sha256} from './store';
import type {BatchImage} from './types';

interface Entry {bytes: number; mime: 'image/png' | 'image/jpeg'; sha256: string}
export const MAX_BATCH_IMAGES = 99;
class Reader {
  private iterator: AsyncIterator<Buffer>;
  private pending = Buffer.alloc(0);
  constructor(request: IncomingMessage) {this.iterator = request[Symbol.asyncIterator]();}
  async read(size: number): Promise<Buffer> {
    if (!this.pending.length) {
      const next = await this.iterator.next();
      if (next.done) throw new Error('图集传输不完整，请重试');
      this.pending = Buffer.from(next.value);
    }
    const data = this.pending.subarray(0, size);
    this.pending = this.pending.subarray(data.length);
    return data;
  }
  async exact(size: number) {
    const parts: Buffer[] = [];
    while (size > 0) {const data = await this.read(size); parts.push(data); size -= data.length;}
    return Buffer.concat(parts);
  }
  async finish() {
    if (this.pending.length || !(await this.iterator.next()).done) throw new Error('图集长度与清单不一致');
  }
}
function manifest(data: Buffer): Entry[] {
  const value: unknown = JSON.parse(data.toString('utf8'));
  if (!value || typeof value !== 'object' || !('images' in value) || !Array.isArray(value.images) || value.images.length < 1 || value.images.length > MAX_BATCH_IMAGES) {
    throw new Error(`每组请选择 1–${MAX_BATCH_IMAGES} 张图片`);
  }
  const entries = value.images as Entry[];
  if (entries.some(item => !item || !Number.isSafeInteger(item.bytes) || item.bytes <= 0 || item.bytes > MAX_BYTES || !['image/png', 'image/jpeg'].includes(item.mime) || !/^[a-f0-9]{64}$/.test(item.sha256))) throw new Error('图集清单无效，单图上限 32 MB');
  if (entries.reduce((sum, item) => sum + item.bytes, 0) > MAX_CACHE_BYTES) throw new Error('整组超过 100 MB，请分成更小的图集');
  return entries;
}
export async function receiveBatch(request: IncomingMessage, directory: string, id: string, expectedHash: string) {
  const reader = new Reader(request);
  const length = (await reader.exact(4)).readUInt32BE();
  if (length < 1 || length > 16384) throw new Error('图集清单大小无效');
  const header = await reader.exact(length);
  if (sha256(header) !== expectedHash) throw new Error('图集清单校验失败');
  const entries = manifest(header);
  const bytes = entries.reduce((sum, item) => sum + item.bytes, 0);
  if (Number(request.headers['content-length']) !== 4 + length + bytes) throw new Error('图集长度与清单不一致');
  const outputs: string[] = [];
  const images: BatchImage[] = [];
  let cachedBytes = 0;
  const groupDirectory = process.platform === 'darwin' && entries.length > 10 ? batchDirectory(directory, id) : undefined;
  try {
    if (groupDirectory) await fs.mkdir(groupDirectory, {recursive: true});
    for (const [index, entry] of entries.entries()) {
      const filename = id + '-' + String(index + 1).padStart(2, '0');
      const stem = path.join(groupDirectory ?? directory, filename);
      const partial = path.join(directory, filename + '.part'); outputs.push(partial);
      const file = await fs.open(partial, 'w');
      const hash = createHash('sha256');
      try {
        let remaining = entry.bytes;
        while (remaining > 0) {const chunk = await reader.read(Math.min(65536, remaining)); hash.update(chunk); await file.write(chunk); remaining -= chunk.length;}
      } finally {await file.close();}
      if (hash.digest('hex') !== entry.sha256) throw new Error(`第 ${index + 1} 张图片传输不完整，请重试`);
      const metadata = await sharp(partial, {limitInputPixels: MAX_PIXELS}).metadata();
      const format = entry.mime === 'image/jpeg' ? 'jpeg' : 'png';
      if (metadata.format !== format || (metadata.pages ?? 1) !== 1) throw new Error('图集仅支持静态 PNG 和 JPEG');
      const imagePath = stem + (format === 'jpeg' ? '.jpg' : '.png');
      const thumbnailPath = path.join(directory, filename + '-thumb.png'); outputs.push(imagePath, thumbnailPath);
      const pipeline = sharp(partial, {limitInputPixels: MAX_PIXELS}).rotate().toColourspace('srgb');
      const result = await (format === 'jpeg' ? pipeline.jpeg({quality: 95}) : pipeline.png()).toFile(imagePath);
      await sharp(imagePath).resize({width: 380, height: 260, fit: 'inside', withoutEnlargement: true}).png().toFile(thumbnailPath);
      cachedBytes += result.size + (await fs.stat(thumbnailPath)).size;
      if (cachedBytes > MAX_CACHE_BYTES) throw new Error('整组处理后超过 100 MB，请分成更小的图集');
      images.push({imagePath, thumbnailPath, width: result.width, height: result.height, mime: entry.mime, bytes: entry.bytes});
      await fs.rm(partial, {force: true, maxRetries: 3, retryDelay: 50});
    }
    await reader.finish();
    return {images, bytes, cachedBytes};
  } catch (error) {
    await Promise.allSettled(outputs.map(file => fs.rm(file, {force: true, maxRetries: 3, retryDelay: 50})));
    if (groupDirectory) await fs.rmdir(groupDirectory).catch(() => {});
    throw error;
  }
}
