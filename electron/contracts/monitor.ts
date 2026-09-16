export type MonitorTarget = {
  transport: 'pty' | 'ssh';
  id: string;
};

export type MonitorStats = {
  cpu: number | null;
  memory: number | null;
  disk: number | null;
  label: string;
};
