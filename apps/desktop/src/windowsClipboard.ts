import path from 'node:path';
import koffi from 'koffi';

const system = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32');
const user32 = koffi.load(path.join(system, 'user32.dll'));
const shell32 = koffi.load(path.join(system, 'shell32.dll'));
const open: (window: null) => number = user32.func('int __stdcall OpenClipboard(void *window)');
const close: () => number = user32.func('int __stdcall CloseClipboard()');
const sequence: () => number = user32.func('uint32_t __stdcall GetClipboardSequenceNumber()');
const available: (format: number) => number = user32.func('int __stdcall IsClipboardFormatAvailable(uint32_t format)');
const data: (format: number) => bigint | null = user32.func('void * __stdcall GetClipboardData(uint32_t format)');
const register: (name: string) => number = user32.func('uint32_t __stdcall RegisterClipboardFormatW(const char16_t *name)');
const queryFile: (drop: bigint, index: number, buffer: Buffer | null, length: number) => number = shell32.func('uint32_t __stdcall DragQueryFileW(void *drop, uint32_t index, _Out_ uint8_t *buffer, uint32_t length)');
const pngFormat = register('PNG');

function readNative<T>(read: () => T): T {
  if (!open(null)) throw new Error('无法访问 Windows 剪贴板，请解锁电脑或稍后重试');
  try {return read();} finally {close();}
}

export function clipboardSequence() {
  return readNative(() => {
    const value = sequence();
    if (!value) throw new Error('Windows 剪贴板暂不可用');
    return value;
  });
}

export function clipboardFiles() {
  return readNative(() => {
    const drop = available(15) ? data(15) : null;
    if (!drop) return [];
    const count = queryFile(drop, 0xffffffff, null, 0);
    if (count > 10000) throw new Error('系统剪贴板文件列表过大');
    return Array.from({length: count}, (_, index) => {
      const length = queryFile(drop, index, null, 0);
      if (!length || length > 32767) throw new Error('系统剪贴板文件路径无效');
      const buffer = Buffer.alloc((length + 1) * 2);
      if (queryFile(drop, index, buffer, length + 1) !== length) throw new Error('系统剪贴板读取失败');
      return buffer.toString('utf16le', 0, length * 2);
    });
  });
}

export function verifyClipboard(filename: string, previous: number) {
  // Electron may return process-local data when Windows rejects clipboard access.
  if (clipboardSequence() === previous) throw new Error('Windows 剪贴板没有更新');
  if (path.extname(filename).toLowerCase() === '.mp4') {
    if (!clipboardFiles().some(file => path.resolve(file).toLowerCase() === path.resolve(filename).toLowerCase())) throw new Error('视频文件尚未写入 Windows 剪贴板');
    return;
  }
  readNative(() => {
    if (![pngFormat, 8, 17].some(format => format && available(format) && data(format))) throw new Error('图片尚未写入 Windows 剪贴板');
  });
}

export function verifyClipboardFiles(filenames: string[], previous: number) {
  if (clipboardSequence() === previous) throw new Error('Windows 剪贴板没有更新');
  const actual = clipboardFiles().map(file => path.resolve(file).toLowerCase());
  if (actual.length !== filenames.length || filenames.some((file, index) => path.resolve(file).toLowerCase() !== actual[index])) throw new Error('图集尚未完整写入 Windows 剪贴板');
}
