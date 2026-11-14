import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import fs from 'node:fs';
import path from 'node:path';
import sharp from 'sharp';

export const MAX_VIDEO_BYTES = 100_000_000;
const execute = promisify(execFile);
interface Probe {format?: {duration?: string; format_name?: string}; streams?: {codec_type?: string; width?: number; height?: number; duration?: string; side_data_list?: {rotation?: number}[]}[]}
export async function inspectVideo(filename: string) {
  const handle = await fs.promises.open(filename, 'r');
  const header = Buffer.alloc(12);
  try {await handle.read(header, 0, header.length, 0);} finally {await handle.close();}
  if (header.toString('ascii', 4, 8) !== 'ftyp') throw new Error('仅支持 MP4 视频');
  const resource = path.join(process.resourcesPath ?? '', 'ffprobe.exe');
  const executable = fs.existsSync(resource) ? resource : path.resolve(__dirname, '../resources/ffprobe.exe');
  const {stdout} = await execute(executable, ['-v', 'error', '-protocol_whitelist', 'file,pipe', '-probesize', '1048576', '-analyzeduration', '2000000', '-show_format', '-show_streams', '-of', 'json', filename], {timeout: 10000, maxBuffer: 65536, windowsHide: true});
  const metadata = JSON.parse(stdout) as Probe;
  const stream = metadata.streams?.find(item => item.codec_type === 'video');
  let width = stream?.width ?? 0; let height = stream?.height ?? 0;
  const durationMs = Math.round(Number(metadata.format?.duration ?? stream?.duration ?? 0) * 1000);
  if (!metadata.format?.format_name?.includes('mp4') || width <= 0 || height <= 0 || width * height > 64_000_000 || !Number.isFinite(durationMs) || durationMs <= 0 || durationMs > 30100) throw new Error('仅支持 30 秒、6400 万像素以内的 MP4 视频');
  const rotation = Math.abs(stream?.side_data_list?.find(item => item.rotation !== undefined)?.rotation ?? 0);
  if (rotation % 180 === 90) [width, height] = [height, width];
  return {width, height, durationMs};
}
export async function videoThumbnail(filename: string, durationMs: number) {
  const seconds = (durationMs / 1000).toFixed(1);
  const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="380" height="240"><rect width="380" height="240" rx="18" fill="#171b22"/><circle cx="190" cy="104" r="35" fill="#323c49"/><path d="M182 87l25 17-25 17z" fill="#d9f278"/><text x="190" y="178" text-anchor="middle" font-family="sans-serif" font-size="16" fill="#dce2ea">MP4 · ' + seconds + ' s</text></svg>';
  await sharp(Buffer.from(svg)).png().toFile(filename);
}
