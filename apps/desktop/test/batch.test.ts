import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import https from 'node:https';
import {randomUUID} from 'node:crypto';
import sharp from 'sharp';
import {Store, sha256} from '../src/store';
import {Receiver} from '../src/receiver';

test('图集整体校验、一次提交、容量与重试', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'imagebridge-batch-'));
  const store = new Store(directory, {seal: value => value, open: value => value});
  const token = 'batch-token'; const clientId = randomUUID();
  store.state.devices.push({clientId, name: '批量测试', tokenHash: sha256(token), pairedAt: Date.now()});
  const commits: string[][] = []; let busy = false;
  const server = new Receiver(store, async () => {}, () => {}, async files => {if (busy) throw new Error('busy'); commits.push([...files]);});
  await server.start(0);
  const agent = new https.Agent({rejectUnauthorized: false});
  const png = await sharp({create: {width: 100, height: 300, channels: 4, background: '#33889988'}}).png().toBuffer();
  const jpeg = await sharp({create: {width: 120, height: 80, channels: 3, background: '#55aa22'}}).withMetadata({orientation: 6}).jpeg().toBuffer();
  function bundle(images: Buffer[] = Array.from({length: 10}, (_, index) => index % 2 ? jpeg : png), bad = false) {
    const header = Buffer.from(JSON.stringify({images: images.map((image, index) => ({bytes: image.length, mime: image === jpeg ? 'image/jpeg' : 'image/png', sha256: bad && index === 2 ? '0'.repeat(64) : sha256(image)}))}));
    const prefix = Buffer.alloc(4); prefix.writeUInt32BE(header.length);
    return {body: Buffer.concat([prefix, header, ...images]), hash: sha256(header)};
  }
  function send(id: string, payload: ReturnType<typeof bundle>, auth = token) {
    return new Promise<{status: number; body: {status: string; error?: string; imageCount?: number}}>((resolve, reject) => {
      const request = https.request({host: '127.0.0.1', port: server.port, path: '/v1/batches', method: 'POST', agent,
        headers: {Authorization: 'Bearer ' + auth, 'Content-Type': 'application/x-imagebridge-batch', 'Content-Length': payload.body.length, 'X-Request-Id': id, 'X-Content-SHA256': payload.hash}}, response => {
        const parts: Buffer[] = []; response.on('data', chunk => parts.push(Buffer.from(chunk)));
        response.on('end', () => resolve({status: response.statusCode!, body: JSON.parse(Buffer.concat(parts).toString())}));
      }); request.on('error', reject); request.end(payload.body);
    });
  }
  try {
    await t.test('10 张独立文件按顺序一次提交，JPEG 保留格式并纠正方向', async () => {
      const id = randomUUID(); const payload = bundle();
      assert.equal((await send(id, payload)).body.status, 'copied'); assert.equal(commits.length, 1); assert.equal(commits[0].length, 10);
      assert.ok(commits[0].every((file, index) => path.basename(file).startsWith(id + '-' + String(index + 1).padStart(2, '0'))));
      const meta = await sharp(commits[0][1]).metadata(); assert.equal(meta.format, 'jpeg'); assert.equal(meta.width, 80); assert.equal(meta.height, 120);
      assert.equal((await sharp(commits[0][0]).metadata()).hasAlpha, true);
      assert.equal((await send(id, payload)).body.status, 'copied'); assert.equal(commits.length, 1);
      assert.equal((await send(id, bundle([png]))).status, 409);
    });
    await t.test('99 张兼容原图集协议并在一次写入中保留顺序', async () => {
      const id = randomUUID();
      const before = commits.length;
      const result = await send(id, bundle(Array<Buffer>(99).fill(png)));
      assert.equal(result.body.status, 'copied');
      assert.equal(result.body.imageCount, 99);
      assert.equal(commits.length, before + 1);
      assert.deepEqual(commits[before].map(file => path.basename(file)),
        Array.from({length: 99}, (_, i) => `${id}-${String(i + 1).padStart(2, '0')}.png`));
    });
    await t.test('坏图、100 张、无授权和传输截断均不能复制半组', async () => {
      const before = commits.length;
      assert.equal((await send(randomUUID(), bundle(undefined, true))).body.status, 'failed');
      assert.equal((await send(randomUUID(), bundle(Array<Buffer>(100).fill(png)))).body.status, 'failed');
      assert.equal((await send(randomUUID(), bundle(), 'wrong')).status, 401);
      const truncated = bundle(); truncated.body = truncated.body.subarray(0, truncated.body.length - 1);
      assert.equal((await send(randomUUID(), truncated)).body.status, 'failed');
      assert.equal(commits.length, before);
    });
    await t.test('剪贴板失败不确认成功，释放整组暂存后同 ID 可重试', async () => {
      const id = randomUUID(); const payload = bundle(); const previous = store.state.clipboardRequestId;
      busy = true; const result = await send(id, payload); assert.equal(result.body.status, 'failed');
      assert.equal(store.state.clipboardRequestId, previous);
      assert.ok(!fs.readdirSync(store.cache).some(file => file.startsWith(id)));
      busy = false; assert.equal((await send(id, payload)).body.status, 'copied');
      assert.equal(store.state.clipboardRequestId, id);
    });
    await t.test('整组总缓存包括全部图片和缩略图，FIFO 不能拆散当前图集', async () => {
      await store.prune();
      const current = store.state.transfers.find(item => item.requestId === store.state.clipboardRequestId)!;
      const actual = current.images!.reduce((sum, image) => sum + fs.statSync(image.imagePath).size + fs.statSync(image.thumbnailPath).size, 0);
      assert.equal(current.cachedBytes, actual);
      const old = store.state.transfers.find(item => item.images && item !== current)!;
      const handle = await fs.promises.open(old.images![0].imagePath, 'r+'); await handle.truncate(99_999_999); await handle.close(); await store.measure(old).catch(() => {old.cachedBytes = 100_000_001;});
      const paths = old.images!.flatMap(image => [image.imagePath, image.thumbnailPath]);
      await store.prune(); assert.ok(paths.every(file => !fs.existsSync(file)));
      assert.ok(current.images!.every(image => fs.existsSync(image.imagePath)));
      assert.ok(store.state.transfers.reduce((sum, item) => sum + (item.cachedBytes ?? 0), 0) <= 100_000_000);
    });
  } finally {await server.stop(); agent.destroy(); fs.rmSync(directory, {recursive: true, force: true});}
});
