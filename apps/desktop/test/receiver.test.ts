import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import https from 'node:https';
import {randomUUID} from 'node:crypto';
import sharp from 'sharp';
import {Store, sha256, MAX_BYTES} from '../src/store';
import {Receiver} from '../src/receiver';

test('配对、加密上传、剪贴板确认与恢复策略', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'imagebridge-test-'));
  const store = new Store(directory, {seal: value => value, open: value => value});
  let copies = 0; let clipboardBusy = false;
  const server = new Receiver(store, async () => {if (clipboardBusy) throw new Error('busy'); copies++;}, () => {});
  await server.start(0);
  const agent = new https.Agent({rejectUnauthorized: false});
  async function request(route: string, body?: Buffer, token?: string, headers: Record<string, string> = {}) {
    return new Promise<{status: number; body: Record<string, unknown>}>((resolve, reject) => {
      const req = https.request({host: '127.0.0.1', port: server.port, agent, path: route, method: body ? 'POST' : 'GET',
        headers: {...(body ? {'Content-Length': String(body.length)} : {}), ...(token ? {Authorization: 'Bearer ' + token} : {}), ...headers}}, res => {
        const chunks: Buffer[] = []; res.on('data', chunk => chunks.push(Buffer.from(chunk))); res.on('end', () => resolve({status: res.statusCode!, body: JSON.parse(Buffer.concat(chunks).toString()) as Record<string, unknown>}));
      }); req.on('error', reject); req.end(body);
    });
  }
  const invitation = server.pairing();
  const pairBody = Buffer.from(JSON.stringify({clientId: randomUUID(), name: '测试 Android', code: invitation.code}));
  const paired = await request('/v1/pair', pairBody); const token = String(paired.body.token);
  const png = await sharp({create: {width: 640, height: 480, channels: 4, background: {r: 7, g: 33, b: 88, alpha: .5}}}).png().toBuffer();
  const headers = (id = randomUUID(), hash = sha256(png)) => ({'Content-Type': 'image/png', 'X-Request-Id': id, 'X-Content-SHA256': hash});
  try {
    await t.test('配对码只能使用一次，刷新会使旧码失效', async () => {
      assert.equal(paired.status, 201); assert.equal((await request('/v1/pair', pairBody)).status, 403);
      const old = server.pairing(); server.pairing();
      assert.equal((await request('/v1/pair', Buffer.from(JSON.stringify({clientId: randomUUID(), name: 'X', code: old.code})))).status, 403);
    });
    await t.test('未授权和浏览器跨站请求不能上传', async () => {
      assert.equal((await request('/v1/images', png, 'invalid', headers())).status, 401);
      assert.equal((await request('/v1/images', png, token, {...headers(), Origin: 'https://example.com'})).status, 403);
      assert.equal(copies, 0);
    });
    await t.test('透明图片成功复制且重复请求不重复覆盖', async () => {
      const id = randomUUID(); const first = await request('/v1/images', png, token, headers(id));
      assert.equal(first.body.status, 'copied'); assert.equal(copies, 1);
      assert.equal((await request('/v1/images', png, token, headers(id))).body.status, 'copied'); assert.equal(copies, 1);
      const item = store.state.transfers.find(value => value.requestId === id)!;
      const meta = await sharp(item.imagePath!).metadata(); assert.equal(meta.hasAlpha, true); assert.equal(meta.width, 640);
      assert.equal((await request('/v1/images', png, token, headers(id, '0'.repeat(64)))).status, 409);
    });
    await t.test('校验失败与超限不能进入剪贴板', async () => {
      assert.equal((await request('/v1/images', png, token, headers(randomUUID(), '1'.repeat(64)))).status, 422);
      assert.equal((await request('/v1/images', png, token, {...headers(), 'Content-Length': String(MAX_BYTES + 1)})).status, 413);
      assert.equal(copies, 1);
    });
    await t.test('剪贴板占用返回 received，手动重试恢复且并发重试只复制一次', async () => {
      const id = randomUUID(); clipboardBusy = true;
      assert.equal((await request('/v1/images', png, token, headers(id))).body.status, 'received');
      assert.equal((await request('/v1/transfers/' + id, undefined, token)).body.status, 'received');
      clipboardBusy = false;
      await Promise.all([request('/v1/images', png, token, headers(id)), request('/v1/images', png, token, headers(id))]);
      assert.equal(copies, 2);
    });
    await t.test('连续发送高像素 JPEG 和截图会释放 Windows 文件句柄与发送锁', async () => {
      const jpeg = await sharp({create: {width: 3000, height: 4000, channels: 3, background: '#285bbd'}}).jpeg().toBuffer();
      const photoId = randomUUID();
      const photo = await request('/v1/images', jpeg, token, {...headers(photoId, sha256(jpeg)), 'Content-Type': 'image/jpeg'});
      assert.equal(photo.body.status, 'copied');
      assert.equal((await request('/v1/images', png, token, headers())).body.status, 'copied');
      for (let attempt = 0; attempt < 100 && fs.existsSync(path.join(store.cache, photoId + '.part')); attempt++) await new Promise(resolve => setTimeout(resolve, 10));
      assert.equal(fs.existsSync(path.join(store.cache, photoId + '.part')), false);
      assert.equal(copies, 4);
    });
    await t.test('长截图保持像素，EXIF 方向被归正，超像素图片被拒绝', async () => {
      const longImage = await sharp({create: {width: 100, height: 12000, channels: 4, background: '#ffeedd'}}).png().toBuffer();
      const longResult = await request('/v1/images', longImage, token, headers(randomUUID(), sha256(longImage)));
      assert.equal(longResult.body.status, 'copied'); assert.equal(longResult.body.height, 12000);
      const rotated = await sharp({create: {width: 120, height: 80, channels: 3, background: '#22aaff'}}).withMetadata({orientation: 6}).jpeg().toBuffer();
      const result = await request('/v1/images', rotated, token, {...headers(randomUUID(), sha256(rotated)), 'Content-Type': 'image/jpeg'});
      assert.equal(result.body.width, 80); assert.equal(result.body.height, 120);
      const oversized = await sharp({create: {width: 8001, height: 8000, channels: 3, background: '#ffffff'}}).png().toBuffer();
      const rejected = await request('/v1/images', oversized, token, headers(randomUUID(), sha256(oversized)));
      assert.equal(rejected.body.status, 'failed');
    });
    await t.test('多个手机独立授权并共享单台接收端，不能读取彼此的传输', async () => {
      const invitation = server.pairing();
      const second = await request('/v1/pair', Buffer.from(JSON.stringify({clientId: randomUUID(), name: '第二台手机', code: invitation.code})));
      const secondToken = String(second.body.token); const id = randomUUID();
      const results = await Promise.all([request('/v1/images', png, token, headers(id)), request('/v1/images', png, secondToken, headers())]);
      assert.ok(results.every(result => result.body.status === 'copied'));
      assert.equal((await request('/v1/transfers/' + id, undefined, secondToken)).status, 404);
      assert.equal((await request('/v1/images', png, secondToken, headers(id))).status, 409);
    });
    await t.test('视频独立接口验证格式、大小、去重与元数据', async () => {
      const video = fs.readFileSync(path.join(__dirname, 'fixtures/one-second.mp4')); const id = randomUUID();
      const extra = {...headers(id, sha256(video)), 'Content-Type': 'video/mp4'};
      const result = await request('/v1/videos', video, token, extra);
      assert.equal(result.body.status, 'copied'); assert.equal(result.body.mime, 'video/mp4');
      assert.equal(result.body.width, 160); assert.ok(Number(result.body.durationMs) >= 900);
      const count = copies;
      assert.equal((await request('/v1/videos', video, token, extra)).body.status, 'copied'); assert.equal(copies, count);
      assert.equal((await request('/v1/videos', png, token, {...headers(), 'Content-Type': 'video/mp4'})).status, 415);
      assert.equal((await request('/v1/videos', video, token, {...extra, 'X-Request-Id': randomUUID(), 'Content-Length': String(100 * 1024 * 1024 + 1)})).status, 413);
      const tooLong = fs.readFileSync(path.join(__dirname, 'fixtures/thirty-one-seconds.mp4'));
      const rejected = await request('/v1/videos', tooLong, token, {...headers(randomUUID(), sha256(tooLong)), 'Content-Type': 'video/mp4'});
      assert.equal(rejected.status, 415); assert.match(String(rejected.body.error), /30 秒/);
    });
    await t.test('慢速删除不阻塞新文件复制和应答，已淘汰请求重试不再次覆盖剪贴板', async () => {
      await store.prune();
      const id = randomUUID(); const filename = path.join(store.cache, id + '.png');
      const file = await fs.promises.open(filename, 'w'); await file.truncate(100_000_000); await file.close();
      const old = {requestId: id, clientId: store.state.devices[0].clientId, clientName: '测试', sha256: sha256(png), status: 'copied' as const, bytes: 1, createdAt: 1, imagePath: filename};
      await store.measure(old); store.state.transfers.push(old);
      let releaseDelete!: () => void;
      const gate = new Promise<void>(resolve => {releaseDelete = resolve;});
      const original = fs.promises.rm.bind(fs.promises);
      const mocked = t.mock.method(fs.promises, 'rm', async (...args: Parameters<typeof fs.promises.rm>) => {
        if (args[0] === filename) await gate;
        return original(...args);
      });
      try {
        const response = await request('/v1/images', png, token, headers());
        assert.equal(response.body.status, 'copied'); assert.equal(fs.existsSync(filename), true);
      } finally {releaseDelete(); await store.prune(); mocked.mock.restore();}
      assert.equal(fs.existsSync(filename), false);
      const count = copies;
      assert.equal((await request('/v1/images', png, token, headers(id))).body.status, 'copied');
      assert.equal(copies, count);
    });
    await t.test('暂停和撤销设备立即生效', async () => {
      store.state.settings.receiving = false;
      assert.equal((await request('/v1/images', png, token, headers())).status, 503);
      store.state.settings.receiving = true; store.state.devices = [];
      assert.equal((await request('/v1/images', png, token, headers())).status, 401);
    });
    await t.test('重启修复中断状态，容量足够时保留超过 24 小时的图片', async () => {
      await store.prune();
      const old = store.state.transfers.find(item => item.imagePath)!; old.createdAt = Date.now() - 90_000_000; const oldPath = old.imagePath!;
      store.state.transfers.push({requestId: randomUUID(), clientId: randomUUID(), clientName: '测试', status: 'receiving', createdAt: Date.now(), bytes: 0, sha256: '0'.repeat(64)});
      store.save();
      const reopened = new Store(directory, {seal: value => value, open: value => value});
      assert.equal(reopened.state.transfers.some(item => item.status === 'receiving'), false);
      await reopened.prune();
      assert.equal(fs.existsSync(oldPath), true);
    });
  } finally {agent.destroy(); await server.stop(); fs.rmSync(directory, {recursive: true, force: true});}
});
