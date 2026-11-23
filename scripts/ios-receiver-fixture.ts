import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import sharp from '../apps/desktop/node_modules/sharp';
import {Receiver, addresses} from '../apps/desktop/src/receiver';
import {Store} from '../apps/desktop/src/store';

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
  const invitation = receiver.pairing();
  if (!addresses().length) throw new Error('No private IPv4 interface available on test runner');
  const image = await sharp({create:{width:48,height:32,channels:4,background:{r:36,g:150,b:90,alpha:0.6}}}).png().toBuffer();
  fs.writeFileSync(output, JSON.stringify({uri: 'imagebridge://pair?data=' + encodeURIComponent(JSON.stringify(invitation)), image: image.toString('base64')}));
  const stop = async () => {
    await receiver.stop();
    fs.writeFileSync(output + '.result', JSON.stringify({clipboardWrites: copied, successfulTransfers: store.state.transfers.filter(item => item.status === 'copied').length}));
    fs.rmSync(directory, {recursive:true,force:true}); process.exit(0);
  };
  process.on('SIGTERM', () => { void stop(); });
  process.on('SIGINT', () => { void stop(); });
}
main().catch(error => { process.stderr.write(String(error) + '\n'); process.exitCode = 1; });
