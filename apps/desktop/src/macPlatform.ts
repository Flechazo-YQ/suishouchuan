import {execFile} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {promisify} from 'node:util';

const execute = promisify(execFile);

async function run(operation: 'copy-image' | 'copy-files' | 'read-files' | 'video', filenames: string[]) {
  const bundled = process.resourcesPath && path.join(process.resourcesPath, 'commandv-mac');
  const executable = bundled && fs.existsSync(bundled) ? bundled : path.resolve(__dirname, '../resources/commandv-mac');
  try {
    const {stdout} = await execute(executable, [operation, ...filenames], {timeout: 10000, maxBuffer: 16384});
    return stdout;
  } catch (error) {
    const failure = error as NodeJS.ErrnoException & {stderr?: string};
    throw new Error(failure.stderr?.trim() || (failure.code === 'ENOENT' ? '缺少 CommandV 的 macOS 组件' : 'macOS 素材处理失败'), {cause: error});
  }
}

export async function copyMacImage(filename: string) {
  await run('copy-image', [filename]);
}

export async function copyMacFiles(filenames: string[]) {
  await run('copy-files', filenames);
}

export async function readMacClipboardFiles(): Promise<string[]> {
  return JSON.parse(await run('read-files', [])) as string[];
}

export async function inspectMacVideo(filename: string) {
  return JSON.parse(await run('video', [filename])) as {width: number; height: number; durationMs: number};
}
