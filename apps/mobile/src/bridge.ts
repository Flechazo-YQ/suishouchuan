import {NativeModules, PermissionsAndroid, Platform} from 'react-native';
export interface Photo {path: string; uri: string; mime: string; bytes: number; width: number; height: number; requestId: string; durationMs?: number}
export interface PhotoBatch {requestId: string; images: Photo[]; autoSend?: boolean}
export interface Device {deviceId: string; name: string; addresses: string[]; port: number; fingerprint: string}
export interface MobileState {devices: Device[]; defaultId: string; discovered: Device[]; sharedError: string}
interface BridgeNative {
  getState(): Promise<string>; takePending(): Promise<string | null>;
  takePairing(): Promise<string | null>;
  discover(): Promise<void>; stopDiscovery(): void;
  checkConnection(id: string): Promise<boolean>;
  selectDevice(id: string): Promise<string>; removeDevice(id: string): Promise<string>;
  pair(uri: string): Promise<string>; scanQr(): Promise<string | null>; capture(): Promise<string | null>;
  record(): Promise<string | null>; stopRecording(): void;
  discard(path: string): void;
  pickImages(): Promise<void>; createBatch(images: string): Promise<string>;
  sendBatch(deviceId: string, batch: string): Promise<string>;
  startScreenCapture(): Promise<void>;
  send(deviceId: string, photo: string): Promise<string>;
}
export const bridge = NativeModules.ImageBridge as BridgeNative;
export async function permission(camera = false) {
  if (camera) {
    const result = await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.CAMERA);
    if (result !== PermissionsAndroid.RESULTS.GRANTED) throw new Error('需要相机权限才能扫码或拍照，可在系统设置中开启。');
  }
  if (Platform.OS === 'android' && Number(Platform.Version) >= 37) {
    const result = await PermissionsAndroid.request('android.permission.ACCESS_LOCAL_NETWORK' as Parameters<typeof PermissionsAndroid.request>[0]);
    if (result !== PermissionsAndroid.RESULTS.GRANTED) throw new Error('需要局域网权限才能连接电脑，可在系统设置中开启。');
  }
}
export async function readState(): Promise<MobileState> {return JSON.parse(await bridge.getState()) as MobileState;}
