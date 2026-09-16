export type ConnectionState = 'Disconnected' | 'Connecting' | 'Connected' | 'Reconnecting' | 'Failed';

export type TerminalTransport = 'pty' | 'ssh';

export type TerminalPayload = {
  id: string;
  data: string;
};

export type TerminalClosedPayload = {
  id: string;
  code?: number;
};

export type ConnectionStatePayload = {
  id: string;
  state: ConnectionState;
  message?: string;
};
