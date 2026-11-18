import React, {useEffect, useState} from 'react';
import {createRoot} from 'react-dom/client';
import type {DesktopApi, DesktopState} from './types';
declare global {interface Window {bridge: DesktopApi}}
function Mark() {return <svg viewBox="0 0 32 32" width="32" height="32" aria-hidden="true"><rect width="32" height="32" rx="9" fill="#2563eb"/><path d="M7 11h5l2-3h5l2 3h4v13H7z" fill="white"/><circle cx="16" cy="17" r="4" fill="#2563eb"/></svg>;}
const labels = {receiving: '接收中', received: '待复制', copied: '已复制', failed: '发送失败'};
function App() {
  const [state, setState] = useState<DesktopState>();
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [pairing, setPairing] = useState<{qr: string; expiresAt: number; uri: string}>();
  const [now, setNow] = useState(Date.now());
  const [busy, setBusy] = useState(false);
  const [tab, setTab] = useState<'images' | 'devices'>('images');
  const previewId = new URLSearchParams(location.search).get('preview');
  async function refresh() {try {setState(await window.bridge.state());} catch (err) {setError(String(err));}}
  useEffect(() => {void refresh(); const off = window.bridge.changed(() => void refresh()); const clock = setInterval(() => setNow(Date.now()), 1000); return () => {off(); clearInterval(clock);};}, []);
  async function action(operation: () => Promise<unknown>, success = '') {
    setError(''); setBusy(true);
    try {await operation(); setNotice(success); await refresh();} catch (err) {setError(String(err).replace(/^Error:.*?: /, ''));} finally {setBusy(false);}
  }
  if (!state) return <main className="loading">正在连接接收服务…{error}</main>;
  if (previewId) {
    const item = state.transfers.find(value => value.requestId === previewId);
    return <div className="toast" onClick={() => void action(() => window.bridge.open(previewId))} role="button" tabIndex={0} onKeyDown={event => {if (event.key === 'Enter') void window.bridge.open(previewId);}}>
      {item?.thumbnail && <img src={item.thumbnail} alt="刚收到的素材"/>}<div><strong><span className="dot"/>{item?.imageCount ? `${item.imageCount} 张图片已复制` : item?.mime === 'video/mp4' ? '视频文件已复制' : '图片已复制'}</strong><p>{item?.mime === 'video/mp4' ? '可粘贴到文件夹或支持视频的软件' : '回到输入框，按 Ctrl+V'}</p><small>{item?.mime === 'video/mp4' ? '点击播放视频' : '点击查看大图'}</small></div></div>;
  }
  return <div className="shell">
    <header><div className="brand"><Mark/><strong>CtrlV</strong><span>手机图片，随手即达</span></div><span className={'status ' + (!state.settings.receiving ? 'paused' : '')}><i/>{state.settings.receiving ? '正在接收' : '接收已暂停'}</span></header>
    <main className="layout"><aside>
      <div className="eyebrow">这台电脑</div><h2>{state.name}</h2><p className="muted">{state.addresses.join(' / ') || '尚未连接局域网'}</p>
      <button className="primary" disabled={busy} onClick={() => void action(async () => setPairing(await window.bridge.pair()))}>＋ 配对手机</button>
      <p className="hint">首次扫码，以后确认发送即可。</p>
      <div className="divider"/>
      <button className={'nav ' + (tab === 'images' ? 'active' : '')} onClick={() => setTab('images')}>最近收到 <span>{state.transfers.length}</span></button>
      <button className={'nav ' + (tab === 'devices' ? 'active' : '')} onClick={() => setTab('devices')}>我的设备 <span>{state.devices.length}</span></button>
      <div className="aside-bottom"><label className="toggle"><input type="checkbox" checked={state.settings.receiving} onChange={event => void action(() => window.bridge.settings({receiving: event.target.checked}))}/>允许接收图片</label>
      <label className="toggle"><input type="checkbox" checked={state.settings.launchAtLogin} onChange={event => void action(() => window.bridge.settings({launchAtLogin: event.target.checked}))}/>开机启动</label><small>仅在局域网传输 · v{state.version}</small></div>
    </aside><section className="content">
      <div className="section-head"><div><div className="eyebrow">{tab === 'images' ? 'YOUR INBOX' : 'CONNECTED DEVICES'}</div><h1>{tab === 'images' ? '图片到了，直接粘贴。' : '只接收你的设备。'}</h1><p className="muted">{tab === 'images' ? '截图分享或拍照确认后，在支持图片的输入框按 Ctrl+V。' : '配对后无需逐张确认。移除设备后，需要重新扫码。'}</p></div><span className="shortcut">Ctrl <b>+</b> V</span></div>
      {(error || state.warning) && <div role="alert" className="alert">{error || state.warning}</div>}
      {notice && <div role="status" className="notice" onClick={() => setNotice('')}>{notice}</div>}
      {tab === 'images' && !state.transfers.length && <div className="empty"><div className="empty-icon"><Mark/></div><h3>等待第一张图片</h3><p>手机系统截图 → 分享到「CtrlC」或「CommandC」<br/>或者打开 App，拍一张照片。</p><div className="steps"><span>01 扫码配对</span><span>02 手机发送</span><span>03 电脑粘贴</span></div></div>}
      {tab === 'images' && <div className="gallery">{state.transfers.map(item => <article key={item.requestId} className="photo"><button className="image-button" disabled={!item.thumbnail} onClick={() => void action(() => window.bridge.open(item.requestId))}>{item.thumbnail ? <img src={item.thumbnail} alt={`${item.clientName} 发来的图片`}/> : <span>{labels[item.status]}</span>}</button><div className="photo-info"><strong>{item.imageCount ? `${item.imageCount} 张图集 · ` : ''}{labels[item.status]}</strong><span>{new Date(item.createdAt).toLocaleTimeString('zh-CN', {hour: '2-digit', minute: '2-digit'})}</span></div><p>{item.clientName} · {item.imageCount ? '一次 Ctrl+V 粘贴整组' : item.width ? `${item.width} × ${item.height}` : '等待处理'}</p>{item.error && <p className="item-error">{item.error}</p>}<div className="photo-actions"><button disabled={busy || !item.imagePath} onClick={() => void action(() => window.bridge.copy(item.requestId), '已重新复制，可以粘贴了')}>重新复制</button><button disabled={busy || !item.imagePath} onClick={() => void action(() => window.bridge.save(item.requestId))}>另存为</button></div></article>)}</div>}
      {tab === 'devices' && <div className="devices">{!state.devices.length && <div className="empty"><h3>还没有配对手机</h3><p>点击左侧「配对手机」，用 App 扫描二维码。</p></div>}{state.devices.map(device => <div className="device" key={device.clientId}><div className="device-icon">▯</div><div><strong>{device.name}</strong><p>配对于 {new Date(device.pairedAt).toLocaleDateString('zh-CN')}</p></div><button disabled={busy} onClick={() => {if (confirm(`移除 ${device.name}？之后需要重新扫码。`)) void action(() => window.bridge.revoke(device.clientId));}}>移除</button></div>)}</div>}
      <footer>照片与视频共用 100 MB 临时缓存 · 空间不足时自动清理最早收到的素材</footer>
    </section></main>
    {pairing && <div className="modal-backdrop" role="presentation"><section className="modal" role="dialog" aria-modal="true" aria-labelledby="pair-title"><button className="close" aria-label="关闭配对" onClick={() => setPairing(undefined)}>×</button><div className="eyebrow">一次配对，随时发送</div><h2 id="pair-title">用手机 App 扫一扫</h2><p className="muted">确认手机与电脑连在可互通的局域网。</p><img className={'qr ' + (pairing.expiresAt <= now ? 'expired' : '')} src={pairing.qr} alt="手机配对二维码"/><p>{pairing.expiresAt > now ? `二维码 ${Math.ceil((pairing.expiresAt - now) / 1000)} 秒后失效` : '二维码已失效，请刷新'}</p><button disabled={busy} onClick={() => void action(async () => setPairing(await window.bridge.pair()))}>刷新二维码</button><details><summary>扫码不方便？查看配对内容</summary><textarea readOnly value={pairing.uri} aria-label="配对内容"/></details>{state.downloadUrl && <details><summary>手机还没安装？查看 APK 下载地址</summary><p className="download">{state.downloadUrl}</p></details>}</section></div>}
  </div>;
}
createRoot(document.getElementById('root')!).render(<App/>);
