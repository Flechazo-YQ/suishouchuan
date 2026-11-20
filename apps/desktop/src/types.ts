export type TransferStatus = 'receiving' | 'received' | 'copied' | 'failed';
export interface BatchImage {imagePath: string; thumbnailPath: string; width: number; height: number; mime: 'image/png' | 'image/jpeg'; bytes: number}
export interface Transfer {
  requestId: string; clientId: string; clientName: string; sha256: string;
  status: TransferStatus; createdAt: number; copiedAt?: number;
  bytes: number; width?: number; height?: number; error?: string;
  imagePath?: string; thumbnailPath?: string; elapsedMs?: number;
  mime?: 'image/png' | 'image/jpeg' | 'video/mp4'; durationMs?: number;
  images?: BatchImage[]; imageCount?: number;
  cachedBytes?: number; cacheExpired?: boolean;
}
export interface Device { clientId: string; name: string; tokenHash: string; pairedAt: number }
export interface Settings { receiving: boolean; launchAtLogin: boolean }
export interface Pairing {
  v: 1; deviceId: string; name: string; addresses: string[]; port: number;
  fingerprint: string; code: string; expiresAt: number;
}
export interface DesktopState {
  isMac?: boolean;
  version: string; name: string; deviceId: string; addresses: string[]; port: number;
  fingerprint: string; settings: Settings; devices: Omit<Device, 'tokenHash'>[];
  transfers: (Transfer & {thumbnail?: string})[]; warning?: string;
  downloadUrl?: string;
}
export interface DesktopApi {
  state(): Promise<DesktopState>;
  pair(): Promise<{qr: string; expiresAt: number; uri: string}>;
  settings(settings: Partial<Settings>): Promise<void>;
  revoke(clientId: string): Promise<void>;
  copy(requestId: string): Promise<void>;
  save(requestId: string): Promise<void>;
  open(requestId: string): Promise<void>;
  changed(listener: () => void): () => void;
}
