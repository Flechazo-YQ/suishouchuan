import React, {useEffect, useRef, useState} from 'react';
import {ActivityIndicator, Alert, Animated, AppState, DeviceEventEmitter, Image, Linking, Modal, PermissionsAndroid, Pressable, requireNativeComponent, ScrollView, StatusBar, Text, TextInput, View, type ViewProps} from 'react-native';
import {SafeAreaProvider, SafeAreaView} from 'react-native-safe-area-context';
import {bridge, permission, readState, type MobileState, type Photo, type PhotoBatch} from './bridge';
import {styles as s} from './styles';
import {CaptureModeTabs, GalleryButton, ScreenCaptureButton, useCaptureModeMotion} from './CameraControls';
import {draftFiles, emptyDraft, finishDraft, receiveDraft, selectDraft, type CaptureDraft, type DraftShelf} from './DraftShelf';

const Camera = requireNativeComponent<ViewProps & {active: boolean}>('ImageBridgeCameraView');
const Video = requireNativeComponent<ViewProps & {path: string}>('ImageBridgeVideoView');
function Screen() {
  const [state, setState] = useState<MobileState>({devices: [], defaultId: '', discovered: [], sharedError: ''});
  const latestState = useRef(state);
  const [connections, setConnections] = useState<Record<string, boolean>>({});
  const probedRoutes = useRef(new Map<string, string>());
  const presenceGeneration = useRef(0);
  const applicationActive = useRef(true);
  const [shelf, setShelf] = useState<DraftShelf>({active: emptyDraft(), saved: []});
  const shelfRef = useRef(shelf);
  const {photo, photos, group, batchMode, reviewing, reviewIndex} = shelf.active;
  function updateShelf(next: DraftShelf) {shelfRef.current = next; setShelf(next);}
  function patchDraft(patch: Partial<CaptureDraft>) {updateShelf({...shelfRef.current, active: {...shelfRef.current.active, ...patch}});}
  function setPhoto(value: Photo | undefined) {patchDraft({photo: value});}
  function setPhotos(value: Photo[] | ((current: Photo[]) => Photo[])) {patchDraft({photos: typeof value === 'function' ? value(shelfRef.current.active.photos) : value});}
  function setGroup(value: PhotoBatch | undefined) {patchDraft({group: value});}
  function setBatchMode(value: boolean) {patchDraft({batchMode: value});}
  function setReviewing(value: boolean) {patchDraft({reviewing: value});}
  function setReviewIndex(value: number) {patchDraft({reviewIndex: value});}
  const working = useRef(false);
  const refreshing = useRef(false);
  const waiting = useRef<Photo | PhotoBatch | undefined>(undefined);
  const [allowed, setAllowed] = useState(false);
  const [foreground, setForeground] = useState(true);
  const [ready, setReady] = useState(false);
  const [busy, setBusy] = useState(false);
  const [recording, setRecording] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [devices, setDevices] = useState(false);
  const [scanning, setScanning] = useState(false);
  const [manual, setManual] = useState(false);
  const [uri, setUri] = useState('');
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const fingerDown = useRef(false);
  const longPress = useRef(false);
  const recordingRef = useRef(false);
  const target = state.devices.find(device => device.deviceId === state.defaultId);
  const video = photo?.mime === 'video/mp4';
  const reviewPhoto = reviewing ? photos[Math.min(reviewIndex, photos.length - 1)] : undefined;
  const modeLocked = busy || recording || !!photo || photos.length > 0 || devices || scanning || !foreground;
  const modeMotion = useCaptureModeMotion(batchMode, modeLocked, next => {setBatchMode(next); setError(''); setNotice('');});
  function connectionText(id: string) {
    return connections[id] === undefined ? '正在检测连接…' : connections[id] ? '已连接' : '未连接';
  }
  function checkConnections(latest: MobileState, periodic = false) {
    if (!applicationActive.current) return;
    const generation = presenceGeneration.current;
    const routes = probedRoutes.current;
    for (const device of latest.devices) {
      const discovered = latest.discovered.find(found => found.deviceId === device.deviceId);
      const endpoint = discovered ?? device;
      const route = `${Boolean(discovered)}/${endpoint.port}/${endpoint.addresses.join(',')}`;
      if (!periodic && routes.get(device.deviceId) === route) continue;
      routes.set(device.deviceId, route);
      void bridge.checkConnection(device.deviceId).catch(() => false).then(connected => {
        if (generation !== presenceGeneration.current || routes.get(device.deviceId) !== route) return;
        setConnections(previous => previous[device.deviceId] === connected ? previous : {...previous, [device.deviceId]: connected});
      });
    }
    for (const id of routes.keys()) {
      if (!latest.devices.some(device => device.deviceId === id)) routes.delete(id);
    }
  }
  async function refresh() {
    if (refreshing.current) return;
    refreshing.current = true;
    try {
      const latest = await readState(); latestState.current = latest; setState(latest); checkConnections(latest);
      const link = await bridge.takePairing(); if (link) confirmPair(link);
      if (working.current) return;
      if (!waiting.current) {
        const incoming = await bridge.takePending();
        if (incoming) waiting.current = JSON.parse(incoming) as Photo | PhotoBatch;
      }
      if (working.current || !waiting.current) return;
      const value = waiting.current; waiting.current = undefined;
      updateShelf(receiveDraft(shelfRef.current, value));
      setError(''); setNotice('');
      if ('images' in value && value.autoSend && latest.defaultId) void sendGroup(value, latest.defaultId);
      else if (!latest.defaultId) {setDevices(true); setNotice('先连接电脑，素材会保留供发送');}
    } catch (err) {setError(String(err));} finally {refreshing.current = false;}
  }
  useEffect(() => {
    void refresh();
    void PermissionsAndroid.check(PermissionsAndroid.PERMISSIONS.CAMERA).then(setAllowed);
    void bridge.discover().catch(() => {});
    const interval = setInterval(() => {if (AppState.currentState === 'active') void refresh();}, 1500);
    const presenceInterval = setInterval(() => checkConnections(latestState.current, true), 15 * 60_000);
    const activity = AppState.addEventListener('change', value => {
      applicationActive.current = value === 'active';
      presenceGeneration.current++;
      setForeground(value === 'active');
      if (value === 'active') {
        probedRoutes.current.clear(); setConnections({});
        void refresh(); void PermissionsAndroid.check(PermissionsAndroid.PERMISSIONS.CAMERA).then(setAllowed);
        void bridge.discover().catch(() => {});
      } else {bridge.stopRecording(); bridge.stopDiscovery();}
    });
    const camera = DeviceEventEmitter.addListener('ImageBridgeCamera', (value: {ready: boolean; error: string}) => {
      setReady(value.ready); if (value.error) setError(value.error);
    });
    return () => {presenceGeneration.current++; clearInterval(interval); clearInterval(presenceInterval); activity.remove(); camera.remove(); bridge.stopRecording(); bridge.stopDiscovery();};
  }, []);
  useEffect(() => {
    if (!recording) return;
    const start = Date.now(); const clock = setInterval(() => setSeconds(Math.floor((Date.now() - start) / 1000)), 200);
    return () => clearInterval(clock);
  }, [recording]);
  async function run(task: () => Promise<void>) {
    if (working.current) return;
    working.current = true;
    setBusy(true); setError(''); setNotice('');
    try {await task(); await refresh();} catch (err) {setError(err instanceof Error ? err.message : String(err));} finally {working.current = false; setBusy(false);}
  }
  function confirmPair(value: string) {
    let name: string;
    try {name = (JSON.parse(decodeURIComponent(value.split('?data=')[1])) as {name: string}).name;}
    catch {setError('请扫描电脑端的配对二维码'); return;}
    Alert.alert('配对电脑', '允许向「' + name + '」发送照片和视频？', [
      {text: '取消', style: 'cancel'},
      {text: '确认配对', onPress: () => void run(async () => {
        await permission(); await bridge.pair(value); await bridge.discover(); setDevices(false); setManual(false); setUri(''); setNotice('配对成功');
      })},
    ]);
  }
  async function scan() {
    await permission(true); setAllowed(true); setScanning(true);
    try {const result = await bridge.scanQr(); if (result) confirmPair(result);} finally {setScanning(false);}
  }
  async function takePhoto() {
    if (longPress.current || busy) return;
    if (batchMode && photos.length >= 10) {setNotice('已收集 10 张，先发送这一组'); return;}
    await run(async () => {
      const result = await bridge.capture(); if (!result) return;
      const image = JSON.parse(result) as Photo;
      if (batchMode) {
        if (photos.reduce((sum, item) => sum + item.bytes, image.bytes) > 100_000_000) {bridge.discard(image.path); throw new Error('整组超过 100 MB，请先发送现有照片');}
        setPhotos(value => [...value, image]); setGroup(undefined);
      } else setPhoto(image);
    });
  }
  async function record() {
    longPress.current = true;
    if (busy || !ready || batchMode) return;
    if (!await PermissionsAndroid.check(PermissionsAndroid.PERMISSIONS.RECORD_AUDIO)) {
      const result = await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.RECORD_AUDIO);
      setNotice(result === PermissionsAndroid.RESULTS.GRANTED ? '录音已允许，请再次长按开始录像' : '需要麦克风权限才能录像');
      return;
    }
    if (!fingerDown.current) return;
    setSeconds(0); setRecording(true); recordingRef.current = true;
    await run(async () => {
      try {const result = await bridge.record(); if (result) setPhoto(JSON.parse(result) as Photo);}
      finally {setRecording(false); recordingRef.current = false;}
    });
  }
  function release() {fingerDown.current = false; if (recordingRef.current) bridge.stopRecording();}
  function retake() {if (photo) bridge.discard(photo.path); updateShelf(finishDraft(shelfRef.current)); setError(''); setNotice('');}
  async function sendGroup(pending: PhotoBatch | undefined, deviceId: string) {
    await run(async () => {
      const value = pending ?? JSON.parse(await bridge.createBatch(JSON.stringify(photos))) as PhotoBatch;
      setGroup(value);
      await permission(); await bridge.discover();
      const result = JSON.parse(await bridge.sendBatch(deviceId, JSON.stringify(value))) as {status: string; error?: string; clientElapsedMs?: number; phoneTemporaryFiles?: number};
      if (result.status !== 'copied') throw new Error(result.error || '整组尚未复制，请重试');
      updateShelf(finishDraft(shelfRef.current));
      setNotice(value.images.length + ' 张已复制到电脑 · 一次 Ctrl+V 粘贴' + (result.clientElapsedMs ? '\n' + (result.clientElapsedMs / 1000).toFixed(1) + ' 秒' : '') + (result.phoneTemporaryFiles === 0 ? ' · 手机临时素材已清理' : ''));
    });
  }
  function confirmGroup() {
    if (working.current || photos.length === 0) return;
    if (!reviewing) {setReviewing(true); return;}
    if (!target) {setDevices(true); setNotice('先配对一台电脑，图集会保留供发送'); return;}
    void sendGroup(group, target.deviceId);
  }
  function removePhoto(image: Photo) {
    bridge.discard(image.path); setPhotos(value => value.filter(item => item.path !== image.path)); setGroup(undefined); setError('');
    if (photos.length === 1) updateShelf(finishDraft(shelfRef.current));
  }
  function confirmSend() {
    if (!photo) return;
    if (!target) {setDevices(true); setNotice('先配对一台电脑，再发送'); return;}
    Alert.alert(video ? '发送视频' : '发送照片', '直接上传到「' + target.name + '」？', [
      {text: '取消', style: 'cancel'}, {text: '确认上传', onPress: () => void run(async () => {
        await permission(); await bridge.discover();
        const result = JSON.parse(await bridge.send(target.deviceId, JSON.stringify(photo))) as {status: string; error?: string; clientElapsedMs?: number; phoneTemporaryFiles?: number};
        if (result.status !== 'copied') throw new Error(result.error || '电脑尚未复制，请重试');
        updateShelf(finishDraft(shelfRef.current));
        setNotice((video ? '视频文件' : '图片') + '已复制到电脑' + (result.clientElapsedMs ? ' · ' + (result.clientElapsedMs / 1000).toFixed(1) + ' 秒' : '') + (result.phoneTemporaryFiles === 0 ? '\n手机临时素材已清理' : ''));
      })},
    ]);
  }
  const feedback = error || state.sharedError || notice;
  useEffect(() => () => {
    const current = shelfRef.current;
    for (const item of [current.active, ...current.saved]) for (const media of draftFiles(item)) bridge.discard(media.path);
    const pending = waiting.current;
    if (pending) for (const media of 'images' in pending ? pending.images : [pending]) bridge.discard(media.path);
  }, []);
  return <SafeAreaView style={s.safe}><StatusBar barStyle="light-content"/>
    <View style={s.top}>
      {photo ? <Pressable onPress={retake} disabled={busy} style={s.topAction} accessibilityRole="button" accessibilityLabel="重新拍摄"><Text style={s.cross}>×</Text></Pressable> :
        <Pressable disabled={busy} onPress={() => setDevices(true)} style={s.deviceLabel} accessibilityRole="button"><View style={[s.dot, target && connections[target.deviceId] && s.pairedDot]}/><View style={s.deviceText}><Text style={s.deviceName} numberOfLines={1}>{target?.name || '未配置电脑'}</Text><Text style={s.deviceIp}>{target ? connectionText(target.deviceId) : '轻触连接电脑'}</Text></View></Pressable>}
      {photos.length > 0 ? <Pressable disabled={busy} onPress={confirmGroup} style={[s.sendGroup, busy && {opacity: .5}]} accessibilityRole="button" accessibilityLabel={reviewing ? '确认并发送 ' + photos.length + ' 张图片' : '查看 ' + photos.length + ' 张图片'} accessibilityState={{disabled: busy, busy}}><Text style={s.sendGroupText}>{busy ? '处理中…' : reviewing ? '确认并发送' : '查看 ' + photos.length + ' 张'}</Text></Pressable> : photo ? <Pressable onPress={confirmSend} disabled={busy} style={s.topAction} accessibilityRole="button" accessibilityLabel="确认上传"><Text style={s.check}>✓</Text></Pressable> :
        <Pressable disabled={busy} onPress={() => setDevices(true)} style={s.topAction} accessibilityRole="button" accessibilityLabel="扫码配对电脑"><View style={s.scanIcon}><View style={s.scanLine}/></View></Pressable>}
    </View>
    <View style={s.viewfinder} {...modeMotion.panHandlers}>
      {!photo && !reviewPhoto && <Animated.View style={[s.fill, modeMotion.pageStyle]}>
        <Camera style={s.fill} active={allowed && foreground && !scanning && !devices}/>
        {allowed && <View style={s.fill} pointerEvents="none"><View style={[s.gridVertical, {left: '33.333%'}]}/><View style={[s.gridVertical, {left: '66.666%'}]}/><View style={[s.gridHorizontal, {top: '33.333%'}]}/><View style={[s.gridHorizontal, {top: '66.666%'}]}/></View>}
      </Animated.View>}
      {reviewPhoto && <Image style={s.fill} source={{uri: reviewPhoto.uri}} resizeMode="contain" accessibilityLabel={'图集预览第 ' + (Math.min(reviewIndex, photos.length - 1) + 1) + ' 张'}/>}
      {photo && (video ? <Video style={s.fill} path={photo.path}/> : <Image style={s.fill} source={{uri: photo.uri}} resizeMode="contain" accessibilityLabel="拍摄预览"/>)}
      {!allowed && !photo && !reviewPhoto && <View style={s.permission}><Text style={s.permissionTitle}>让眼前，即刻到电脑</Text><Text style={s.permissionBody}>允许使用相机后即可拍摄</Text><Pressable style={s.permissionButton} onPress={() => void run(async () => {await permission(true); setAllowed(true);})}><Text style={s.permissionButtonText}>开启相机</Text></Pressable><Pressable style={s.settingsButton} onPress={() => void Linking.openSettings()}><Text style={s.secondaryText}>系统权限设置</Text></Pressable></View>}
      {recording && <View style={s.recordBadge}><View style={s.recordDot}/><Text style={s.recordTime}>{'00:' + String(seconds).padStart(2, '0')}</Text></View>}
      {busy && !recording && <View style={s.processing}><ActivityIndicator color="white"/><Text style={s.processingText}>正在处理…</Text></View>}
      {!!feedback && <Pressable style={[s.feedback, !!(error || state.sharedError) && s.error]} onPress={() => {setError(''); setNotice('');}} accessibilityLiveRegion="polite"><Text style={s.feedbackText}>{feedback}</Text></Pressable>}
    </View>
    {shelf.saved.length > 0 && <ScrollView horizontal style={{maxHeight: 52, backgroundColor: '#111'}} contentContainerStyle={{padding: 6, gap: 8}}>{shelf.saved.map((saved, index) => <Pressable key={draftFiles(saved)[0].path} disabled={busy} accessibilityRole="button" accessibilityLabel={'返回待发' + (saved.photo ? '素材' : saved.photos.length + '张图集')} onPress={() => {if (!working.current) {updateShelf(selectDraft(shelfRef.current, index)); setError(''); setNotice('');}}} style={{paddingHorizontal: 12, minHeight: 40, borderRadius: 20, backgroundColor: '#293025', justifyContent: 'center'}}><Text style={{color: '#d9f278', fontSize: 12}}>{saved.photo?.mime === 'video/mp4' ? '待发视频' : '待发 ' + (saved.photo ? 1 : saved.photos.length) + ' 张'} · 查看</Text></Pressable>)}</ScrollView>}
    {photos.length > 0 && <ScrollView horizontal style={s.strip} contentContainerStyle={s.stripContent}>{photos.map((image, index) => <View key={image.path} style={s.tile}><Pressable disabled={busy} onPress={() => {setReviewIndex(index); setReviewing(true);}} accessibilityLabel={'预览第 ' + (index + 1) + ' 张'}><Image source={{uri: image.uri}} style={s.tileImage}/></Pressable><Text style={s.tileNumber}>{index + 1}</Text><Pressable disabled={busy} style={s.tileRemove} accessibilityLabel={'移除第 ' + (index + 1) + ' 张'} onPress={() => removePhoto(image)}><Text style={s.tileCross}>×</Text></Pressable></View>)}</ScrollView>}
    <View style={[s.bottom, !photo && !reviewPhoto && s.captureBottom]}>
      {!photo && !reviewPhoto && <CaptureModeTabs batch={batchMode} disabled={modeLocked || modeMotion.transitioning} progress={modeMotion.progress} onSelect={modeMotion.selectMode}/>}
      <Text style={s.hint}>{reviewPhoto ? '点缩略图查看 · × 移除 · 右上角确认并发送' : photo ? (video ? '预览静音播放 · 点击右上角确认上传' : '点击右上角确认上传 · 左上角重新拍摄') : batchMode ? '连续点按拍照 · 最多 10 张' : recording ? '松手完成 · 最长 30 秒' : '轻触拍照，按住录像'}</Text>
      {reviewPhoto && <View style={s.previewMeta}><Text style={s.metaTitle}>预览 {Math.min(reviewIndex, photos.length - 1) + 1} / {photos.length}</Text><Text style={s.metaDetail} numberOfLines={1}>发送到：{target?.name || '未配置电脑'}</Text><Pressable disabled={busy} onPress={() => setReviewing(false)}><Text style={s.secondaryText}>返回取景</Text></Pressable></View>}
      {!photo && !reviewPhoto && <View style={s.captureRow}>
        <GalleryButton disabled={busy || recording || modeMotion.transitioning} onPress={() => void run(async () => {await bridge.pickImages();})}/>
        <Pressable accessibilityRole="button" accessibilityLabel={batchMode ? '连拍：拍摄一张并继续取景' : '拍摄：轻触拍照，长按录像'} disabled={!allowed || !ready || (busy && !recording) || modeMotion.transitioning} delayLongPress={350} onPressIn={() => {fingerDown.current = true; longPress.current = false;}} onPressOut={release} onLongPress={batchMode ? undefined : () => void record()} onPress={() => void takePhoto()} style={[s.shutterRing, recording && s.recordRing, (!allowed || !ready || modeMotion.transitioning) && s.shutterDisabled]}><View style={[s.shutter, recording && s.recordShutter]}/></Pressable>
        <ScreenCaptureButton disabled={busy || recording || modeMotion.transitioning} onPress={() => void run(async () => {if (!target) {setDevices(true); return;} await bridge.startScreenCapture();})}/>
      </View>}
      {photo && <View style={s.previewMeta}><Text style={s.metaTitle}>{video ? '视频' : '照片'}</Text><Text style={s.metaDetail}>{photo.width} × {photo.height} · {(photo.bytes / 1024 / 1024).toFixed(1)} MB{photo.durationMs ? ' · ' + (photo.durationMs / 1000).toFixed(1) + ' 秒' : ''}</Text></View>}
      <Text style={s.footer}>{photo || reviewPhoto ? 'CtrlC · 仅局域网传输' : photos.length > 0 ? '可切换相册或截屏 · 这组照片会保留' : '左滑连拍 · 右滑拍摄'}</Text>
    </View>
    <Modal visible={devices} transparent animationType="slide" onRequestClose={() => setDevices(false)}><View style={s.backdrop}><SafeAreaView style={s.sheet}><View style={s.sheetTop}><Text style={s.sheetTitle}>连接电脑</Text><Pressable onPress={() => setDevices(false)} style={s.topAction} accessibilityLabel="关闭设备面板"><Text style={s.cross}>×</Text></Pressable></View><Text style={s.sheetDescription}>电脑打开CtrlV，点击「配对手机」。手机扫描二维码后，确认电脑名称。</Text><ScrollView style={s.deviceList}>{state.devices.map(device => <View key={device.deviceId} style={s.deviceRow}><Pressable style={s.deviceChoice} onPress={() => void run(async () => {await bridge.selectDevice(device.deviceId); setDevices(false);})}><Text style={s.deviceName}>{device.name}{device.deviceId === state.defaultId ? '  ✓' : ''}</Text><Text style={s.deviceIp}>{connectionText(device.deviceId)}</Text></Pressable><Pressable style={s.removeButton} onPress={() => Alert.alert('移除电脑', '移除「' + device.name + '」？', [{text: '取消'}, {text: '移除', style: 'destructive', onPress: () => void run(async () => {await bridge.removeDevice(device.deviceId);})}])}><Text style={s.secondaryText}>移除</Text></Pressable></View>)}</ScrollView><Pressable style={s.pairButton} disabled={busy} onPress={() => void run(scan)}><Text style={s.pairText}>扫描配对二维码</Text></Pressable><Pressable style={s.settingsButton} onPress={() => setManual(!manual)}><Text style={s.secondaryText}>手动输入配对内容</Text></Pressable>{manual && <><TextInput style={s.input} value={uri} onChangeText={setUri} autoCapitalize="none" multiline placeholder="imagebridge://pair?data=…" placeholderTextColor="#777"/><Pressable style={s.pairButton} onPress={() => confirmPair(uri.trim())}><Text style={s.pairText}>确认配对</Text></Pressable></>}{!!error && <Text style={s.sheetError}>{error}</Text>}</SafeAreaView></View></Modal>
  </SafeAreaView>;
}
export default function App() {return <SafeAreaProvider><Screen/></SafeAreaProvider>;}
