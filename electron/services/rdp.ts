export { rdpService, RdpService, FreeRdpAdapter } from './rdp/RdpService.js';
export type { RdpConnectInput, IRdpAdapter } from './rdp/RdpService.js';

import type { BrowserWindow } from 'electron';
import { rdpService, type RdpConnectInput } from './rdp/RdpService.js';

/** @deprecated Prefer rdpService */
export function connectRdp(window: BrowserWindow, input: RdpConnectInput) {
  return rdpService.connect(window, input);
}

/** @deprecated Prefer rdpService */
export function disconnectRdp(id: string) {
  rdpService.disconnect(id);
}
