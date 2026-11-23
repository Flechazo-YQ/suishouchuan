import fs from 'node:fs';
import https from 'node:https';
import os from 'node:os';
import path from 'node:path';
import sharp from '../apps/desktop/node_modules/sharp';
import {Receiver, addresses} from '../apps/desktop/src/receiver';
import {Store, sha256} from '../apps/desktop/src/store';

async function main() {
  const output = process.argv[2];
  if (!output) throw new Error('Fixture output path is required');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'commandv-receiver-'));
  const store = new Store(directory, {seal: value => value, open: value => value});
  let copied = 0;
  const receiver = new Receiver(store, async file => { await sharp(file).metadata(); copied += 1; }, () => {}, async files => {
    if (files.length !== 99) throw new Error('Unexpected image count');
    await Promise.all(files.map(file => sharp(file).metadata())); copied += 1;
  });
  await receiver.start(0);
  const legacy = https.createServer({key: store.tls.key, cert: store.tls.cert}, (req, res) => {
    const token = req.headers.authorization?.replace(/^Bearer /, '') ?? '';
    const valid = store.state.devices.some(device => device.tokenHash === sha256(token));
    res.writeHead(valid ? 404 : 401, {'Content-Type': 'application/json'});
    const lookup = req.url === '/v1/transfers/00000000-0000-0000-0000-000000000000';
    res.end(JSON.stringify({error: !valid ? '配对已失效' : lookup ? '未找到发送记录，可以重试' : '接口不存在'}));
  });
  await new Promise<void>(resolve => legacy.listen(0, '0.0.0.0', resolve));
  const legacyAddress = legacy.address();
  if (!legacyAddress || typeof legacyAddress === 'string') throw new Error('Legacy test listener unavailable');
  const invitation = receiver.pairing();
  if (!addresses().length) throw new Error('No private IPv4 interface available on test runner');
  const image = await sharp({create:{width:48,height:32,channels:4,background:{r:36,g:150,b:90,alpha:0.6}}}).png().toBuffer();
  fs.writeFileSync(output, JSON.stringify({uri: 'imagebridge://pair?data=' + encodeURIComponent(JSON.stringify(invitation)), image: image.toString('base64'), legacyPort: legacyAddress.port}));
  const stop = async () => {
    await receiver.stop();
    await new Promise<void>(resolve => legacy.close(() => resolve()));
    fs.writeFileSync(output + '.result', JSON.stringify({clipboardWrites: copied, successfulTransfers: store.state.transfers.filter(item => item.status === 'copied').length}));
    fs.rmSync(directory, {recursive:true,force:true}); process.exit(0);
  };
  process.on('SIGTERM', () => { void stop(); });
  process.on('SIGINT', () => { void stop(); });
}
main().catch(error => { process.stderr.write(String(error) + '\n'); process.exitCode = 1; });
