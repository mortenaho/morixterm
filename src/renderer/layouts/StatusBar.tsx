import { useWorkspace } from '../stores/workspaceStore';
import { useEffect, useState } from 'react';
import { Activity, HardDrive, MemoryStick, Cpu } from 'lucide-react';
import type { MonitorTarget } from '../../../electron/contracts/monitor';

export default function StatusBar({ target }: { target?: MonitorTarget }) {
  const connectionLabel = useWorkspace(state => state.connectionLabel);
  const cols = useWorkspace(state => state.cols);
  const rows = useWorkspace(state => state.rows);
  const [visible, setVisible] = useState(true);
  const [stats, setStats] = useState<{ cpu: number; memory: number; disk: number; label: string } | null>(null);
  useEffect(() => {
    let active = true;
    setStats(null);
    if (!target) return () => { active = false; };
    const update = async () => { const result = await window.mori.monitor.stats(target); if (active && result.ok && result.value) setStats(result.value); };
    void update();
    const timer = window.setInterval(() => void update(), 3000);
    return () => { active = false; window.clearInterval(timer); };
  }, [target]);

  return (
    <footer className="statusbar">
      <span>{connectionLabel}</span>
      <span>UTF-8</span>
      <span>{cols}×{rows}</span>
      <button className="monitor-toggle" onClick={() => setVisible(value => !value)} title={visible ? 'Hide session monitor' : 'Show session monitor'} aria-label={visible ? 'Hide session monitor' : 'Show session monitor'}><Activity size={12}/>{visible ? 'Monitor' : 'Show monitor'}</button>
      {visible && stats && <div className="monitor-metrics"><strong>{stats.label}</strong><span><Cpu size={14}/> CPU {stats.cpu}%</span><span><MemoryStick size={14}/> RAM {stats.memory}%</span><span><HardDrive size={14}/> Disk {stats.disk ? `${stats.disk}%` : '—'}</span></div>}
      <span className="statusbar-brand">Made with care by MoriXterm</span>
    </footer>
  );
}
