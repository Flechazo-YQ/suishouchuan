import assert from 'node:assert/strict';
import {test} from 'node:test';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {randomUUID} from 'node:crypto';
import {Store, MAX_CACHE_BYTES} from '../src/store';
import type {Transfer} from '../src/types';

test('照片视频共享 100 MB，按接收时间淘汰且不影响正在使用的素材', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'imagebridge-cache-'));
  const store = new Store(directory, {seal: value => value, open: value => value});
  let order = Date.now() - 100_000;
  async function add(bytes: number, mime: 'image/png' | 'video/mp4' = 'image/png', thumb = 0) {
    const id = randomUUID();
    const item: Transfer = {requestId: id, clientId: 'test', clientName: 'test', sha256: 'a'.repeat(64), status: 'copied', bytes: 1, createdAt: order++, mime,
      imagePath: path.join(store.cache, id + (mime === 'video/mp4' ? '.mp4' : '.png')), thumbnailPath: path.join(store.cache, id + '-thumb.png')};
    for (const [filename, length] of [[item.imagePath!, bytes], [item.thumbnailPath!, thumb]] as const) {
      const file = await fs.promises.open(filename, 'w'); await file.truncate(length); await file.close();
    }
    await store.measure(item); store.state.transfers.push(item); return item;
  }
  const live = () => store.state.transfers.filter(item => item.imagePath);
  try {
    await t.test('99.27 MB 的 50 张照片再加 1.5 MB，只删除最早一张', async () => {
      const photos = [];
      for (let index = 0; index < 50; index++) photos.push(await add(1_985_400));
      const firstPath = photos[0].imagePath!;
      const latest = await add(1_500_000); await store.prune();
      assert.equal(live().length, 50); assert.equal(fs.existsSync(firstPath), false);
      assert.ok(photos.slice(1).every(item => item.imagePath)); assert.ok(latest.imagePath);
      assert.equal(photos[0].status, 'copied'); assert.equal(photos[0].cacheExpired, true);
      assert.ok(live().reduce((sum, item) => sum + item.cachedBytes!, 0) <= MAX_CACHE_BYTES);
    });
    await t.test('视频和照片统一 FIFO，并计入实际落盘大小及缩略图', async () => {
      for (const item of live()) await store.discard(item);
      const first = await add(25_000_000); const second = await add(25_000_000);
      const video = await add(25_000_000, 'video/mp4', 10_000);
      const photo = await add(20_000_000); await store.prune();
      assert.equal(live().length, 4);
      const latest = await add(10_000_000); await store.prune();
      assert.equal(first.cacheExpired, true); assert.ok(second.imagePath && video.imagePath && photo.imagePath && latest.imagePath);
      await add(75_000_000); await store.prune();
      assert.equal(second.cacheExpired, true); assert.equal(video.cacheExpired, true);
      assert.equal(photo.cacheExpired, true); assert.ok(latest.imagePath);
    });
    await t.test('正在复制的旧文件暂不删除，释放后清理，最新素材始终保留', async () => {
      for (const item of live()) await store.discard(item);
      const old = await add(80_000_000); const unpin = store.pin(old.requestId);
      const newest = await add(70_000_000, 'video/mp4');
      await store.prune(); assert.ok(old.imagePath && newest.imagePath);
      unpin(); await store.prune(); assert.equal(old.cacheExpired, true); assert.ok(newest.imagePath);
    });
    await t.test('超大素材不会挤掉当前缓存；重启按新容量恢复', async () => {
      const count = live().length;
      await assert.rejects(() => add(MAX_CACHE_BYTES, 'video/mp4', 1), /100 MB/);
      assert.equal(live().length, count);
      const orphan = path.join(store.cache, randomUUID() + '.png'); fs.writeFileSync(orphan, 'abandoned conversion');
      store.save(); const reopened = new Store(directory, {seal: value => value, open: value => value});
      await reopened.prune(); assert.equal(reopened.state.transfers.filter(item => item.imagePath).length, count);
      assert.equal(fs.existsSync(orphan), false);
    });
  } finally {await store.prune(); fs.rmSync(directory, {recursive: true, force: true});}
});
