export type MonitorTarget = {
  transport: 'pty' | 'ssh';
  id: string;
};

export type MonitorStats = {
  cpu: number;
  memory: number;
  disk: number;
  label: string;
};
