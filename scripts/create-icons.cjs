const fs = require('node:fs');
const path = require('node:path');
const sharp = require('../apps/desktop/node_modules/sharp');
const root = path.resolve(__dirname, '..');
const svg = Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256"><defs><linearGradient id="metal" x2="0" y2="1"><stop stop-color="#f2f2f4"/><stop offset="1" stop-color="#9ca0a6"/></linearGradient><radialGradient id="glass"><stop stop-color="#395781"/><stop offset=".32" stop-color="#122333"/><stop offset=".7" stop-color="#080e18"/><stop offset="1" stop-color="#35404b"/></radialGradient></defs><rect width="256" height="256" rx="57" fill="url(#metal)"/><rect x="31" y="49" width="194" height="160" rx="30" fill="#222429"/><path d="M77 51l16-20h70l16 20" fill="#222429"/><circle cx="128" cy="126" r="68" fill="#090b0e" stroke="#5c6066" stroke-width="5"/><circle cx="128" cy="126" r="54" fill="url(#glass)" stroke="#7d858f" stroke-width="2"/><circle cx="128" cy="126" r="30" fill="#101722" stroke="#294966" stroke-width="2"/><ellipse cx="108" cy="105" rx="16" ry="10" fill="#668cb9" opacity=".5"/><circle cx="145" cy="143" r="9" fill="#30483a"/><circle cx="199" cy="72" r="7" fill="#d9f278"/></svg>');
(async () => {
  const directory = path.join(root, 'apps/desktop/resources');
  fs.mkdirSync(directory, {recursive: true});
  const png = await sharp(svg).png().toBuffer();
  const header = Buffer.alloc(22); header.writeUInt16LE(1, 2); header.writeUInt16LE(1, 4);
  header.writeUInt16LE(1, 10); header.writeUInt16LE(32, 12); header.writeUInt32LE(png.length, 14); header.writeUInt32LE(22, 18);
  fs.writeFileSync(path.join(directory, 'icon.ico'), Buffer.concat([header, png]));
  for (const [density, size] of Object.entries({mdpi:48, hdpi:72, xhdpi:96, xxhdpi:144, xxxhdpi:192})) {
    const target = path.join(root, 'apps/mobile/android/app/src/main/res/mipmap-' + density);
    fs.mkdirSync(target, {recursive: true});
    const icon = await sharp(svg).resize(size).png().toBuffer();
    fs.writeFileSync(path.join(target, 'ic_launcher.png'), icon);
    fs.writeFileSync(path.join(target, 'ic_launcher_round.png'), icon);
  }
})().catch(error => {process.stderr.write(error.stack + '\n'); process.exitCode = 1;});
