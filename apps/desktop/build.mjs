import {build} from 'esbuild';
import {mkdir, copyFile} from 'node:fs/promises';
await mkdir('dist/renderer', {recursive: true});
await build({entryPoints: ['src/main.ts'], bundle: true, platform: 'node', format: 'cjs', packages: 'external', outfile: 'dist/main.cjs'});
await build({entryPoints: ['src/preload.ts'], bundle: true, platform: 'node', format: 'cjs', external: ['electron'], outfile: 'dist/preload.cjs'});
await build({entryPoints: ['src/ui.tsx'], bundle: true, platform: 'browser', format: 'iife', outfile: 'dist/renderer/ui.js', minify: true, define: {'process.env.NODE_ENV': '"production"'}});
await copyFile('src/index.html', 'dist/renderer/index.html');
await copyFile('src/ui.css', 'dist/renderer/ui.css');
