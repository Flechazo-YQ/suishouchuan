import assert from 'node:assert/strict';
import {test} from 'node:test';
import {draftFiles, emptyDraft, finishDraft, receiveDraft, selectDraft, type DraftShelf} from '../src/DraftShelf';
import type {Photo, PhotoBatch} from '../src/bridge';

const photo = (id: string, mime = 'image/jpeg'): Photo => ({path: id, uri: 'file://' + id, requestId: id, bytes: 100, width: 10, height: 10, mime});
const burst = [photo('burst-1'), photo('burst-2')];
const group: PhotoBatch = {requestId: 'original-retry-id', images: burst};
const original: DraftShelf = {active: {...emptyDraft(true), photos: burst, group, reviewIndex: 1}, saved: []};

test('相册单独发送后恢复原连拍及失败重试ID，不把原照片混入相册上传', () => {
  const incoming: PhotoBatch = {requestId: 'album-id', images: [photo('album')], autoSend: true};
  const switched = receiveDraft(original, incoming);
  assert.deepEqual(draftFiles(switched.active).map(item => item.path), ['album']);
  assert.equal(switched.saved[0].group?.requestId, 'original-retry-id');
  assert.deepEqual(finishDraft(switched), original);
});

test('截图等待确认时保留连拍，返回原组不会删除新截图', () => {
  const incoming: PhotoBatch = {requestId: 'screen-id', images: [photo('screen')], autoSend: false};
  const switched = receiveDraft(original, incoming);
  assert.equal(switched.active.reviewing, true);
  const back = selectDraft(switched, 0);
  assert.deepEqual(back.active.photos, burst);
  assert.equal(back.active.reviewing, true);
  assert.equal(back.saved[0].group?.requestId, 'screen-id');
  assert.deepEqual(selectDraft(back, 0).active.photos, incoming.images);
});

test('录屏预览与原图集独立，放弃或完成录屏后恢复原图集', () => {
  const video = photo('recording.mp4', 'video/mp4');
  const switched = receiveDraft(original, video);
  assert.equal(switched.active.photo, video);
  assert.equal(switched.active.photos.length, 0);
  assert.deepEqual(draftFiles(switched.saved[0]), burst);
  assert.deepEqual(finishDraft(switched), original);
});

test('多次切换保留所有待发素材，完成当前项只移出当前项', () => {
  const album: PhotoBatch = {requestId: 'album-id', images: [photo('album')]};
  const screen: PhotoBatch = {requestId: 'screen-id', images: [photo('screen')]};
  const switched = receiveDraft(receiveDraft(original, album), screen);
  assert.equal(switched.saved.length, 2);
  const afterScreen = finishDraft(switched);
  assert.deepEqual(afterScreen.active.photos, burst);
  assert.deepEqual(afterScreen.saved[0].photos, album.images);
  const afterBurst = finishDraft(afterScreen);
  assert.deepEqual(afterBurst.active.photos, album.images);
  assert.equal(afterBurst.saved.length, 0);
  assert.deepEqual(finishDraft(afterBurst).active.photos, []);
});
